use std::path::Path;

use image::{
    imageops::{resize, FilterType},
    metadata::Orientation,
    DynamicImage, GrayImage, ImageDecoder, ImageReader, Luma, RgbImage,
};
use imageproc::{
    contours::find_contours,
    distance_transform::Norm,
    edges::canny,
    filter::gaussian_blur_f32,
    morphology::dilate,
    point::Point,
};

use crate::error::ScanError;

pub const FALLBACK_QUAD: [(f32, f32); 4] = [
    (0.03, 0.03),
    (0.97, 0.03),
    (0.97, 0.97),
    (0.03, 0.97),
];

/// Open an image file and apply its EXIF orientation before any processing.
pub fn open_oriented_image(path: impl AsRef<Path>) -> Result<DynamicImage, ScanError> {
    let mut decoder = ImageReader::open(path)?
        .with_guessed_format()?
        .into_decoder()?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut img = DynamicImage::from_decoder(decoder)?;
    img.apply_orientation(orientation);
    Ok(img)
}

/// Detect document corners from a camera Y-plane (luma) buffer.
/// Returns `None` if no confident convex quadrilateral is found.
pub fn detect_corners_from_y_plane(
    y: &[u8],
    width: u32,
    height: u32,
    row_stride: u32,
    rotation_deg: u32,
) -> Option<[(f32, f32); 4]> {
    if width < 16 || height < 16 || row_stride < width {
        return None;
    }
    let min_bytes = (height as usize - 1) * (row_stride as usize) + (width as usize);
    if y.len() < min_bytes {
        return None;
    }

    let rot = (rotation_deg % 360) / 90 * 90;
    let (rot_w, rot_h) = match rot {
        90 | 270 => (height, width),
        _ => (width, height),
    };

    let target_long = 400u32;
    let long_side = rot_w.max(rot_h);
    let scale = if long_side > target_long {
        target_long as f32 / long_side as f32
    } else {
        1.0
    };
    let dst_w = ((rot_w as f32 * scale).round() as u32).max(16);
    let dst_h = ((rot_h as f32 * scale).round() as u32).max(16);

    let mut gray = GrayImage::new(dst_w, dst_h);
    let rs = row_stride as usize;
    let w_usize = width as usize;
    let h_usize = height as usize;
    let step_x = rot_w as f32 / dst_w as f32;
    let step_y = rot_h as f32 / dst_h as f32;

    // 2x2 box-averaged sampling reduces sensor noise and text aliasing during downscale.
    let sample_rot = |rx: f32, ry: f32| -> u32 {
        let rx_i = rx.floor().clamp(0.0, (rot_w - 1) as f32) as usize;
        let ry_i = ry.floor().clamp(0.0, (rot_h - 1) as f32) as usize;
        let (sx, sy) = match rot {
            90 => (ry_i, h_usize - 1 - rx_i),
            180 => (w_usize - 1 - rx_i, h_usize - 1 - ry_i),
            270 => (w_usize - 1 - ry_i, rx_i),
            _ => (rx_i, ry_i),
        };
        y[sy * rs + sx] as u32
    };

    for dy in 0..dst_h {
        let ry0 = (dy as f32 + 0.25) * step_y;
        let ry1 = (dy as f32 + 0.75) * step_y;
        for dx in 0..dst_w {
            let rx0 = (dx as f32 + 0.25) * step_x;
            let rx1 = (dx as f32 + 0.75) * step_x;
            let avg = (sample_rot(rx0, ry0)
                + sample_rot(rx1, ry0)
                + sample_rot(rx0, ry1)
                + sample_rot(rx1, ry1)
                + 2)
                >> 2;
            gray.put_pixel(dx, dy, Luma([avg as u8]));
        }
    }

    detect_quad_core(&gray, None, true)
}

/// Detect document corners from a full-resolution image file.
/// Always returns a valid quad (falls back to 3% inset rectangle).
pub fn detect_corners_from_image_file(path: impl AsRef<Path>) -> Result<[(f32, f32); 4], ScanError> {
    let img = open_oriented_image(path)?;
    let rgb_full = img.to_rgb8();
    let (w, h) = rgb_full.dimensions();
    let long_side = w.max(h);
    let target_long = 640u32;

    let rgb = if long_side > target_long {
        let scale = target_long as f32 / long_side as f32;
        let nw = ((w as f32 * scale).round() as u32).max(16);
        let nh = ((h as f32 * scale).round() as u32).max(16);
        resize(&rgb_full, nw, nh, FilterType::Triangle)
    } else {
        rgb_full
    };

    let gray = rgb_to_gray(&rgb);
    let color_dist = rgb_border_distance_map(&rgb);

    Ok(detect_quad_core(&gray, Some(&color_dist), false).unwrap_or(FALLBACK_QUAD))
}

/// Hybrid Gradient-Guided Hough Line + Contour document quad detector with
/// signed polarity scoring, interior homogeneity check, and polarity-aware IRLS refinement.
fn detect_quad_core(
    gray: &GrayImage,
    color_dist: Option<&GrayImage>,
    is_live: bool,
) -> Option<[(f32, f32); 4]> {
    let (w, h) = gray.dimensions();
    if w < 16 || h < 16 {
        return None;
    }

    // 1. Un-dilated Sobel gradient field for accurate scoring, Hough orientation & sub-pixel fitting.
    let blur_eval = gaussian_blur_f32(gray, 1.2);
    let mut grad = compute_sobel(&blur_eval);
    if let Some(cd) = color_dist {
        let cd_blur = gaussian_blur_f32(cd, 1.2);
        let cd_grad = compute_sobel(&cd_blur);
        merge_max_gradient(&mut grad, &cd_grad);
    }

    // 2. Grayscale morphological closing erases dark printed text inside bright paper
    //    while keeping outer document boundaries razor sharp.
    let close_radius = if is_live { 3 } else { 4 };
    let closed = grayscale_close(gray, close_radius);
    let closed_blur = gaussian_blur_f32(&closed, 1.3);
    let raw_blur = gaussian_blur_f32(gray, 1.6);

    // 3. Thin un-dilated Canny edge maps for Gradient-Guided Hough straight-line detection.
    let edges_low = canny(&closed_blur, 14.0, 42.0);
    let edges_med = canny(&closed_blur, 34.0, 96.0);
    let edges_raw = canny(&raw_blur, 28.0, 84.0);

    let mut thin_edges = GrayImage::new(w, h);
    {
        let e1 = edges_low.as_raw();
        let e2 = edges_med.as_raw();
        let dst = thin_edges.as_mut();
        for i in 0..dst.len() {
            if e1[i] > 0 || e2[i] > 0 {
                dst[i] = 255;
            }
        }
    }
    let cd_closed_blur = color_dist.map(|cd| {
        let c = grayscale_close(cd, close_radius);
        gaussian_blur_f32(&c, 1.3)
    });
    if let Some(ref cdb) = cd_closed_blur {
        let e_cd = canny(cdb, 18.0, 56.0);
        let dst = thin_edges.as_mut();
        for (i, &v) in e_cd.as_raw().iter().enumerate() {
            if v > 0 {
                dst[i] = 255;
            }
        }
    }

    let img_area = (w as f64) * (h as f64);
    let min_area = img_area * 0.08;
    let max_area = img_area * 0.985;
    let min_score = if is_live { 0.24 } else { 0.16 };

    let mut best_quad: Option<([(f64, f64); 4], [f64; 4])> = None;
    let mut best_score = min_score;

    let mut evaluate_candidate = |ordered: [(f64, f64); 4], tightness: f64| {
        if !within_frame_margin(&ordered, w as f64, h as f64, 0.04) {
            return;
        }
        let clamped = clamp_quad_to_frame(ordered, w as f64, h as f64);
        if !is_convex_quad(&clamped) {
            return;
        }
        let quad_area = polygon_area(&clamped);
        if quad_area < min_area || quad_area > max_area {
            return;
        }
        if !has_valid_document_geometry(&clamped) {
            return;
        }
        let (score, polarities) = score_quad(
            &clamped,
            &grad,
            &blur_eval,
            &closed,
            tightness,
            img_area,
            w as f64,
            h as f64,
        );
        if score > best_score {
            best_score = score;
            best_quad = Some((clamped, polarities));
        }
    };

    // 4A. Primary generator: Gradient-Guided Hough straight lines -> 4-line intersections.
    //     Reconstructs exact corners even when obstructed by binder clips, shadows, or clutter!
    let lines = extract_hough_lines(&thin_edges, &grad, w, h);
    let line_quads = generate_line_quads(&lines, w as f64, h as f64, min_area, max_area);
    for quad in line_quads {
        evaluate_candidate(quad, 1.0);
    }

    // 4B. Secondary generator: Contour + 4-edge hull collapse (complements curved/low-line scenes).
    let mut contour_maps: Vec<(GrayImage, bool)> = Vec::with_capacity(6);
    contour_maps.push((dilate(&edges_low, Norm::LInf, 1), false));
    contour_maps.push((dilate(&edges_med, Norm::LInf, 1), false));
    contour_maps.push((dilate(&edges_raw, Norm::LInf, 1), false));
    if let Some((bright_mask, dark_mask)) = otsu_masks(&closed_blur) {
        contour_maps.push((bright_mask, true));
        contour_maps.push((dark_mask, true));
    }
    if let Some(ref cdb) = cd_closed_blur {
        if let Some((cd_bright, _)) = otsu_masks(cdb) {
            contour_maps.push((cd_bright, true));
        }
    }

    for (map, is_solid_mask) in &contour_maps {
        let contours = find_contours::<i32>(map);
        for contour in &contours {
            if contour.points.len() < 4 {
                continue;
            }
            let hull = convex_hull_points(&contour.points);
            if hull.len() < 4 {
                continue;
            }
            let hull_area = polygon_area(&hull);
            if hull_area < min_area || hull_area > max_area {
                continue;
            }
            if *is_solid_mask {
                let c_area = polygon_area_i32(&contour.points);
                if c_area / hull_area < 0.65 {
                    continue;
                }
            }
            let Some(quad_pts) = reduce_hull_to_quad(&hull) else {
                continue;
            };
            if !is_convex_quad(&quad_pts) {
                continue;
            }
            let quad_area = polygon_area(&quad_pts);
            if quad_area > hull_area * 1.24 || hull_area > quad_area * 1.24 {
                continue;
            }
            let ordered = order_quad_points(&quad_pts);
            let tightness = (hull_area / quad_area).min(quad_area / hull_area).clamp(0.0, 1.0);
            evaluate_candidate(ordered, tightness);
        }
    }

    let (winner, polarities) = best_quad?;

    // 5. Polarity-aware sub-pixel IRLS line fitting + line-intersection corner refinement.
    let search_radius = if is_live { 6 } else { 10 };
    let refined = refine_quad_corners(winner, polarities, &grad, w as f64, h as f64, search_radius);

    let wf = (w - 1).max(1) as f32;
    let hf = (h - 1).max(1) as f32;
    Some([
        ((refined[0].0 as f32 / wf).clamp(0.0, 1.0), (refined[0].1 as f32 / hf).clamp(0.0, 1.0)),
        ((refined[1].0 as f32 / wf).clamp(0.0, 1.0), (refined[1].1 as f32 / hf).clamp(0.0, 1.0)),
        ((refined[2].0 as f32 / wf).clamp(0.0, 1.0), (refined[2].1 as f32 / hf).clamp(0.0, 1.0)),
        ((refined[3].0 as f32 / wf).clamp(0.0, 1.0), (refined[3].1 as f32 / hf).clamp(0.0, 1.0)),
    ])
}

#[derive(Clone, Copy)]
struct DetectedLine {
    /// Normalized implicit line `a*x + b*y + c = 0` with `a^2 + b^2 = 1` and `theta_deg in [0, 180)`.
    a: f64,
    b: f64,
    c: f64,
    theta_deg: f64,
    strength: f32,
}

/// Fast Gradient-Guided Hough Transform: each Canny pixel only votes within +-2 deg of its own
/// Sobel gradient normal, making it ~36x faster and immune to curved cable/texture clutter.
fn extract_hough_lines(
    thin_edges: &GrayImage,
    grad: &GradientField,
    w: u32,
    h: u32,
) -> Vec<DetectedLine> {
    let wu = w as usize;
    let hu = h as usize;
    if wu < 16 || hu < 16 {
        return Vec::new();
    }

    let diag = ((w as f64).powi(2) + (h as f64).powi(2)).sqrt().ceil();
    let rho_step = 2.0f64;
    let rho_offset = diag;
    let num_rho = ((2.0 * diag) / rho_step).ceil() as usize + 3;
    let num_theta = 180usize;

    let mut cos_tab = [0.0f64; 180];
    let mut sin_tab = [0.0f64; 180];
    for t in 0..180 {
        let rad = (t as f64).to_radians();
        cos_tab[t] = rad.cos();
        sin_tab[t] = rad.sin();
    }

    let mut acc = vec![0.0f32; num_theta * num_rho];
    let raw = thin_edges.as_raw();
    let mut edge_pts: Vec<(f64, f64, f64, f64, f64)> = Vec::with_capacity(4096);

    // Exclude 2px outer border so frame edges never vote as document lines.
    for y in 2..(hu - 2) {
        let row = y * wu;
        let yf = y as f64;
        for x in 2..(wu - 2) {
            if raw[row + x] == 0 {
                continue;
            }
            let idx = row + x;
            let gx = grad.gx[idx] as f64;
            let gy = grad.gy[idx] as f64;
            let mag = (gx * gx + gy * gy).sqrt();
            if mag < 7.0 {
                continue;
            }

            let nx = gx / mag;
            let ny = gy / mag;
            let xf = x as f64;
            edge_pts.push((xf, yf, nx, ny, mag));

            // Flat length-oriented weight: rewards long straight document edges over short dark cables.
            let base_w = (1.0 + (mag / 45.0).min(1.0)) as f32;
            let mut deg = gy.atan2(gx).to_degrees();
            if deg < 0.0 {
                deg += 180.0;
            }
            if deg >= 180.0 {
                deg -= 180.0;
            }
            let base_t = deg.round() as i32;

            for dt in -2..=2 {
                let t_idx = (base_t + dt).rem_euclid(180) as usize;
                let rho = xf * cos_tab[t_idx] + yf * sin_tab[t_idx];
                let r_idx = ((rho + rho_offset) / rho_step).round() as isize;
                if r_idx >= 0 && (r_idx as usize) < num_rho {
                    let w_dt = base_w * (1.0 - 0.15 * dt.abs() as f32);
                    acc[t_idx * num_rho + r_idx as usize] += w_dt;
                }
            }
        }
    }

    let min_peak = (w.min(h) as f32 * 0.12).max(16.0);
    let max_lines = 16usize;
    let cx = w as f64 * 0.5;
    let cy = h as f64 * 0.5;
    let mut lines: Vec<DetectedLine> = Vec::with_capacity(max_lines);

    for _ in 0..32 {
        if lines.len() >= max_lines {
            break;
        }
        let mut best_val = 0.0f32;
        let mut best_idx = 0usize;
        for (idx, &v) in acc.iter().enumerate() {
            if v > best_val {
                best_val = v;
                best_idx = idx;
            }
        }
        if best_val < min_peak {
            break;
        }

        let best_t = best_idx / num_rho;
        let best_r = best_idx % num_rho;
        let peak_rho = best_r as f64 * rho_step - rho_offset;
        let peak_a = cos_tab[best_t];
        let peak_b = sin_tab[best_t];
        let peak_c = -peak_rho;

        // Suppress 2D neighborhood in (theta, rho) including 0 <-> 180 deg sign-flip wrap.
        let r_supp = 6isize; // +-12px
        let t_supp = 8isize; // +-8 deg
        for dt in -t_supp..=t_supp {
            let raw_t = best_t as isize + dt;
            let (t_wrap, flipped) = if raw_t < 0 {
                ((raw_t + 180) as usize, true)
            } else if raw_t >= 180 {
                ((raw_t - 180) as usize, true)
            } else {
                (raw_t as usize, false)
            };
            let target_rho = if flipped { -peak_rho } else { peak_rho };
            let center_r = ((target_rho + rho_offset) / rho_step).round() as isize;
            for dr in -r_supp..=r_supp {
                let ri = center_r + dr;
                if ri >= 0 && (ri as usize) < num_rho {
                    acc[t_wrap * num_rho + ri as usize] = 0.0;
                }
            }
        }

        // Refine peak line via weighted IRLS fit over orientation-aligned inlier edge pixels.
        let mut inliers: Vec<(f64, f64, f64)> = Vec::new();
        for &(ex, ey, enx, eny, mag) in &edge_pts {
            let perp = (peak_a * ex + peak_b * ey + peak_c).abs();
            if perp <= 3.5 {
                let align = (peak_a * enx + peak_b * eny).abs();
                if align >= 0.965 {
                    inliers.push((ex, ey, 1.0 + (mag / 45.0).min(1.0)));
                }
            }
        }

        let (mut la, mut lb, mut lc) = if inliers.len() >= 14 {
            fit_line_irls(&inliers).unwrap_or((peak_a, peak_b, peak_c))
        } else {
            (peak_a, peak_b, peak_c)
        };

        // Canonicalize normal into [0, 180) deg (lb > 0, or lb == 0 && la >= 0).
        if lb < 0.0 || (lb == 0.0 && la < 0.0) {
            la = -la;
            lb = -lb;
            lc = -lc;
        }
        let mut theta_deg = lb.atan2(la).to_degrees();
        if theta_deg < 0.0 {
            theta_deg += 180.0;
        }
        if theta_deg >= 180.0 {
            theta_deg -= 180.0;
        }

        // Deduplicate near-identical refined lines.
        let is_dup = lines.iter().any(|existing| {
            let dot = (existing.a * la + existing.b * lb).abs();
            if dot < 0.992 {
                return false;
            }
            let d1 = existing.a * cx + existing.b * cy + existing.c;
            let sign = if existing.a * la + existing.b * lb >= 0.0 { 1.0 } else { -1.0 };
            let d2 = (la * cx + lb * cy + lc) * sign;
            (d1 - d2).abs() < 10.0
        });
        if !is_dup {
            lines.push(DetectedLine {
                a: la,
                b: lb,
                c: lc,
                theta_deg,
                strength: best_val,
            });
        }
    }

    lines
}

/// Forms candidate convex quadrilaterals by intersecting pairs of roughly opposite straight lines.
fn generate_line_quads(
    lines: &[DetectedLine],
    w: f64,
    h: f64,
    min_area: f64,
    max_area: f64,
) -> Vec<[(f64, f64); 4]> {
    if lines.len() < 4 {
        return Vec::new();
    }

    let cx = w * 0.5;
    let cy = h * 0.5;
    let min_sep = w.min(h) * 0.14;
    let mut out = Vec::new();

    // Two orthogonal partitions (axis-aligned & 45-deg shifted) cover all document rotations.
    for partition in 0..2 {
        let mut group_a: Vec<&DetectedLine> = Vec::new();
        let mut group_b: Vec<&DetectedLine> = Vec::new();

        for l in lines {
            let in_a = if partition == 0 {
                l.theta_deg >= 45.0 && l.theta_deg < 135.0
            } else {
                l.theta_deg < 90.0
            };
            if in_a {
                group_a.push(l);
            } else {
                group_b.push(l);
            }
        }

        group_a.sort_by(|x, y| y.strength.partial_cmp(&x.strength).unwrap_or(std::cmp::Ordering::Equal));
        group_b.sort_by(|x, y| y.strength.partial_cmp(&x.strength).unwrap_or(std::cmp::Ordering::Equal));
        group_a.truncate(8);
        group_b.truncate(8);

        if group_a.len() < 2 || group_b.len() < 2 {
            continue;
        }

        let pairs_of = |grp: &[&DetectedLine]| -> Vec<(usize, usize)> {
            let mut pairs = Vec::new();
            for i in 0..grp.len() {
                for j in (i + 1)..grp.len() {
                    let l1 = grp[i];
                    let l2 = grp[j];
                    let dot = l1.a * l2.a + l1.b * l2.b;
                    // Opposite sides may converge under strong perspective up to ~38 deg.
                    if dot.abs() < 0.78 {
                        continue;
                    }
                    let d1 = l1.a * cx + l1.b * cy + l1.c;
                    let sign = if dot >= 0.0 { 1.0 } else { -1.0 };
                    let d2 = (l2.a * cx + l2.b * cy + l2.c) * sign;
                    if (d1 - d2).abs() >= min_sep {
                        pairs.push((i, j));
                    }
                }
            }
            pairs
        };

        let a_pairs = pairs_of(&group_a);
        let b_pairs = pairs_of(&group_b);

        for &(ai, aj) in &a_pairs {
            let ha = (group_a[ai].a, group_a[ai].b, group_a[ai].c);
            let hb = (group_a[aj].a, group_a[aj].b, group_a[aj].c);
            for &(bi, bj) in &b_pairs {
                let va = (group_b[bi].a, group_b[bi].b, group_b[bi].c);
                let vb = (group_b[bj].a, group_b[bj].b, group_b[bj].c);

                let Some(p0) = intersect_lines(ha, va) else { continue; };
                let Some(p1) = intersect_lines(ha, vb) else { continue; };
                let Some(p2) = intersect_lines(hb, vb) else { continue; };
                let Some(p3) = intersect_lines(hb, va) else { continue; };
                let pts = [p0, p1, p2, p3];

                if !within_frame_margin(&pts, w, h, 0.04) {
                    continue;
                }
                let ordered = order_quad_points(&pts);
                let clamped = clamp_quad_to_frame(ordered, w, h);
                if !is_convex_quad(&clamped) {
                    continue;
                }
                let area = polygon_area(&clamped);
                if area < min_area || area > max_area {
                    continue;
                }
                if !has_valid_document_geometry(&clamped) {
                    continue;
                }
                out.push(clamped);
            }
        }
    }

    out
}

/// Scores a candidate quad using signed directional edge consistency, global polarity agreement,
/// interior homogeneity, corner-clutter rejection, and frame-border penalties.
/// Returns `(score, dominant_side_polarities)` where each polarity is `+1.0` or `-1.0`.
#[allow(clippy::too_many_arguments)]
fn score_quad(
    ordered: &[(f64, f64); 4],
    grad: &GradientField,
    blur_eval: &GrayImage,
    closed: &GrayImage,
    tightness: f64,
    img_area: f64,
    w: f64,
    h: f64,
) -> (f64, [f64; 4]) {
    let cx = (ordered[0].0 + ordered[1].0 + ordered[2].0 + ordered[3].0) * 0.25;
    let cy = (ordered[0].1 + ordered[1].1 + ordered[2].1 + ordered[3].1) * 0.25;

    let mut side_scores = [0.0f64; 4];
    let mut side_polarities = [1.0f64; 4];
    let mut contrast_scores = [0.0f64; 4];
    let samples = 28usize;

    for s in 0..4 {
        let a = ordered[s];
        let b = ordered[(s + 1) % 4];
        let dx = b.0 - a.0;
        let dy = b.1 - a.1;
        let len = (dx * dx + dy * dy).sqrt();
        if len < 12.0 {
            return (0.0, side_polarities);
        }

        // Unit normal pointing inward toward quad center.
        let mut nx = -dy / len;
        let mut ny = dx / len;
        let mx = (a.0 + b.0) * 0.5;
        let my = (a.1 + b.1) * 0.5;
        if nx * (cx - mx) + ny * (cy - my) < 0.0 {
            nx = -nx;
            ny = -ny;
        }

        let mut sum_pos = 0.0f64;
        let mut sum_neg = 0.0f64;
        let mut hits_pos = 0usize;
        let mut hits_neg = 0usize;
        let mut sum_step = 0.0f64;
        let mut step_count = 0usize;

        for k in 0..samples {
            let t = 0.06 + 0.88 * (k as f64 / (samples - 1) as f64);
            let px = a.0 + dx * t;
            let py = a.1 + dy * t;

            // Strongest signed directional gradient within +-2px perpendicular band.
            let mut best_signed = 0.0f64;
            let mut best_abs = 0.0f64;
            for d in -2..=2 {
                let (gx, gy) = grad.sample(px + nx * d as f64, py + ny * d as f64);
                let g_signed = gx * nx + gy * ny;
                if g_signed.abs() > best_abs {
                    best_abs = g_signed.abs();
                    best_signed = g_signed;
                }
            }
            if best_signed > 0.0 {
                sum_pos += best_signed.min(60.0);
                if best_signed >= 8.0 {
                    hits_pos += 1;
                }
            } else if best_signed < 0.0 {
                let v = -best_signed;
                sum_neg += v.min(60.0);
                if v >= 8.0 {
                    hits_neg += 1;
                }
            }

            // Interior vs exterior brightness step at +-4px.
            let ix = (px + nx * 4.0).round() as i32;
            let iy = (py + ny * 4.0).round() as i32;
            let ox = (px - nx * 4.0).round() as i32;
            let oy = (py - ny * 4.0).round() as i32;
            if ix >= 0 && iy >= 0 && ix < w as i32 && iy < h as i32
                && ox >= 0 && oy >= 0 && ox < w as i32 && oy < h as i32
            {
                let inside = blur_eval.get_pixel(ix as u32, iy as u32)[0] as f64;
                let outside = blur_eval.get_pixel(ox as u32, oy as u32)[0] as f64;
                sum_step += inside - outside;
                step_count += 1;
            }
        }

        let dom_sign = if sum_pos >= sum_neg { 1.0 } else { -1.0 };
        side_polarities[s] = dom_sign;
        let dom_sum = sum_pos.max(sum_neg);
        let dom_hits = if dom_sign > 0.0 { hits_pos } else { hits_neg };
        let total_sum = sum_pos + sum_neg;

        let sign_cons = if total_sum > 1e-3 {
            (sum_pos - sum_neg).abs() / total_sum
        } else {
            0.0
        };
        let cov = dom_hits as f64 / samples as f64;
        let mag = (dom_sum / samples as f64 / 40.0).min(1.0);

        // Multiplicative sign consistency crushes lines cutting diagonally across cables/clutter.
        side_scores[s] = (0.35 * mag + 0.45 * cov + 0.20 * sign_cons) * (0.35 + 0.65 * sign_cons);
        contrast_scores[s] = if step_count > 0 {
            let aligned_step = (sum_step / step_count as f64) * dom_sign;
            (aligned_step.max(0.0) / 38.0).min(1.0)
        } else {
            0.0
        };
    }

    let mean_edge = (side_scores[0] + side_scores[1] + side_scores[2] + side_scores[3]) * 0.25;
    let min_edge = side_scores[0]
        .min(side_scores[1])
        .min(side_scores[2])
        .min(side_scores[3]);

    if min_edge < 0.16 || mean_edge < 0.28 {
        return (0.0, side_polarities);
    }

    // Global polarity agreement across all 4 sides (all light-on-dark OR all dark-on-light).
    let pos_sides = side_polarities.iter().filter(|&&p| p > 0.0).count();
    let agree = pos_sides.max(4 - pos_sides);
    let polarity_factor = match agree {
        4 => 1.0,
        3 => 0.85,
        _ => 0.55,
    };

    // Interior homogeneity & corner-clutter rejection on text-erased grayscale image.
    let (homog_factor, corner_factor) = score_interior_homogeneity(ordered, closed, w, h);

    // Per-corner frame-border penalty prevents corners from snapping to (0, 0) frame edges.
    let mut border_penalty = 1.0f64;
    let mut border_corners = 0usize;
    for p in ordered {
        if p.0 <= 2.5 || p.0 >= w - 3.5 || p.1 <= 2.5 || p.1 >= h - 3.5 {
            border_penalty *= 0.86;
            border_corners += 1;
        }
    }
    let quad_area = polygon_area(ordered);
    let area_ratio = quad_area / img_area;
    if border_corners >= 3 && area_ratio > 0.90 {
        border_penalty *= 0.65;
    }

    let edge_score = 0.60 * mean_edge + 0.40 * min_edge;
    let contrast_score =
        (contrast_scores[0] + contrast_scores[1] + contrast_scores[2] + contrast_scores[3]) * 0.25;
    // Reward full-document area over smaller internal sub-rectangles (tables, sharp shadow halves).
    let area_factor = 0.45 + 0.55 * (area_ratio / 0.65).min(1.0).powf(0.65);

    let total = edge_score
        * polarity_factor
        * homog_factor
        * corner_factor
        * border_penalty
        * (0.60 + 0.25 * contrast_score + 0.15 * tightness)
        * area_factor;

    (total, side_polarities)
}

/// Evaluates whether the interior and 4 corner patches of the candidate quad look like a
/// coherent document surface (tolerating soft shadows, rejecting dark desk/cable clutter).
fn score_interior_homogeneity(
    ordered: &[(f64, f64); 4],
    closed: &GrayImage,
    w: f64,
    h: f64,
) -> (f64, f64) {
    let sample_quad = |u: f64, v: f64| -> f64 {
        let px = (1.0 - u) * (1.0 - v) * ordered[0].0
            + u * (1.0 - v) * ordered[1].0
            + u * v * ordered[2].0
            + (1.0 - u) * v * ordered[3].0;
        let py = (1.0 - u) * (1.0 - v) * ordered[0].1
            + u * (1.0 - v) * ordered[1].1
            + u * v * ordered[2].1
            + (1.0 - u) * v * ordered[3].1;
        let ix = px.round().clamp(0.0, w - 1.0) as u32;
        let iy = py.round().clamp(0.0, h - 1.0) as u32;
        closed.get_pixel(ix, iy)[0] as f64
    };

    const GRID: [f64; 7] = [0.07, 0.21, 0.35, 0.50, 0.65, 0.79, 0.93];
    let mut vals = [0.0f64; 49];
    let mut k = 0;
    for &v in &GRID {
        for &u in &GRID {
            vals[k] = sample_quad(u, v);
            k += 1;
        }
    }
    vals.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let med_in = vals[24];

    // Threshold 75 tolerates soft hand/phone shadows on white paper (~40-65 drop)
    // while strongly penalizing dark background desk/cables (~120-190 drop).
    let bad_count = vals.iter().filter(|&&v| (v - med_in).abs() > 75.0).count();
    let bad_frac = bad_count as f64 / 49.0;
    let homog_factor = (1.0 - 0.85 * bad_frac).clamp(0.30, 1.0);

    // Check 4 corner patches (4 points per corner): a small binder clip hits at most 1-2 points,
    // whereas a corner pulled into dark cables/desk hits 3-4 points.
    let corner_uvs: [[(f64, f64); 4]; 4] = [
        [(0.05, 0.05), (0.13, 0.05), (0.05, 0.13), (0.13, 0.13)], // TL
        [(0.95, 0.05), (0.87, 0.05), (0.95, 0.13), (0.87, 0.13)], // TR
        [(0.95, 0.95), (0.87, 0.95), (0.95, 0.87), (0.87, 0.87)], // BR
        [(0.05, 0.95), (0.13, 0.95), (0.05, 0.87), (0.13, 0.87)], // BL
    ];
    let mut corner_factor = 1.0f64;
    for patch in &corner_uvs {
        let bad_in_corner = patch
            .iter()
            .filter(|&&(u, v)| (sample_quad(u, v) - med_in).abs() > 70.0)
            .count();
        if bad_in_corner >= 3 {
            corner_factor *= 0.55;
        }
    }

    (homog_factor, corner_factor)
}

/// Refines each of the 4 sides via polarity-aware IRLS weighted line fitting on directional Sobel
/// peaks, then intersects the 4 refined lines to obtain sub-pixel accurate corners.
fn refine_quad_corners(
    ordered: [(f64, f64); 4],
    polarities: [f64; 4],
    grad: &GradientField,
    w: f64,
    h: f64,
    search_radius: i32,
) -> [(f64, f64); 4] {
    let cx = (ordered[0].0 + ordered[1].0 + ordered[2].0 + ordered[3].0) * 0.25;
    let cy = (ordered[0].1 + ordered[1].1 + ordered[2].1 + ordered[3].1) * 0.25;
    let mut lines = [(0.0f64, 0.0f64, 0.0f64); 4];
    let samples = 36usize;

    for s in 0..4 {
        let a = ordered[s];
        let b = ordered[(s + 1) % 4];
        let orig_line = line_from_points(a, b);
        let dx = b.0 - a.0;
        let dy = b.1 - a.1;
        let len = (dx * dx + dy * dy).sqrt();
        if len < 16.0 {
            lines[s] = orig_line;
            continue;
        }

        // Inward unit normal.
        let mut nx = -dy / len;
        let mut ny = dx / len;
        let mx = (a.0 + b.0) * 0.5;
        let my = (a.1 + b.1) * 0.5;
        if nx * (cx - mx) + ny * (cy - my) < 0.0 {
            nx = -nx;
            ny = -ny;
        }
        let dom_sign = polarities[s];

        let mut pts: Vec<(f64, f64, f64)> = Vec::with_capacity(samples);
        let r = search_radius.min((len * 0.12) as i32).max(3);

        for k in 0..samples {
            let t = 0.08 + 0.84 * (k as f64 / (samples - 1) as f64);
            let px = a.0 + dx * t;
            let py = a.1 + dy * t;

            let mut best_d = 0i32;
            let mut best_g = -1.0f64;
            let mut profile = Vec::with_capacity((2 * r + 1) as usize);

            for d in -r..=r {
                let (gx, gy) = grad.sample(px + nx * d as f64, py + ny * d as f64);
                // Only match edges with the same polarity as this document side.
                let g = ((gx * nx + gy * ny) * dom_sign).max(0.0);
                profile.push(g);
                if g > best_g {
                    best_g = g;
                    best_d = d;
                }
            }

            if best_g < 9.0 {
                continue;
            }

            // 3-point parabolic sub-pixel peak refinement.
            let idx = (best_d + r) as usize;
            let sub = if idx > 0 && idx + 1 < profile.len() {
                let g_prev = profile[idx - 1];
                let g_curr = profile[idx];
                let g_next = profile[idx + 1];
                let denom = g_prev - 2.0 * g_curr + g_next;
                if denom.abs() > 1e-6 {
                    (0.5 * (g_prev - g_next) / denom).clamp(-0.5, 0.5)
                } else {
                    0.0
                }
            } else {
                0.0
            };

            let offset = best_d as f64 + sub;
            pts.push((px + nx * offset, py + ny * offset, best_g.min(60.0)));
        }

        if pts.len() >= 12 {
            if let Some(fitted) = fit_line_irls(&pts) {
                let cos_align = (fitted.0 * orig_line.0 + fitted.1 * orig_line.1).abs();
                if cos_align >= 0.975 {
                    lines[s] = fitted;
                    continue;
                }
            }
        }
        lines[s] = orig_line;
    }

    let Some(tl) = intersect_lines(lines[0], lines[3]) else { return ordered; };
    let Some(tr) = intersect_lines(lines[0], lines[1]) else { return ordered; };
    let Some(br) = intersect_lines(lines[2], lines[1]) else { return ordered; };
    let Some(bl) = intersect_lines(lines[2], lines[3]) else { return ordered; };
    let candidate = [tl, tr, br, bl];

    let max_shift = (w * w + h * h).sqrt() * 0.06;
    for i in 0..4 {
        if !candidate[i].0.is_finite() || !candidate[i].1.is_finite() {
            return ordered;
        }
        if dist(candidate[i], ordered[i]) > max_shift {
            return ordered;
        }
    }
    if !within_frame_margin(&candidate, w, h, 0.02) {
        return ordered;
    }
    let clamped = clamp_quad_to_frame(candidate, w, h);
    if is_convex_quad(&clamped) && has_valid_document_geometry(&clamped) {
        clamped
    } else {
        ordered
    }
}

struct GradientField {
    w: u32,
    h: u32,
    gx: Vec<f32>,
    gy: Vec<f32>,
}

impl GradientField {
    #[inline]
    fn sample(&self, x: f64, y: f64) -> (f64, f64) {
        let max_x = (self.w - 1) as f64;
        let max_y = (self.h - 1) as f64;
        if x < 0.0 || y < 0.0 || x > max_x || y > max_y {
            return (0.0, 0.0);
        }
        let x0 = x.floor() as u32;
        let y0 = y.floor() as u32;
        let x1 = (x0 + 1).min(self.w - 1);
        let y1 = (y0 + 1).min(self.h - 1);
        let fx = x - x0 as f64;
        let fy = y - y0 as f64;
        let w_u = self.w as usize;

        let i00 = y0 as usize * w_u + x0 as usize;
        let i10 = y0 as usize * w_u + x1 as usize;
        let i01 = y1 as usize * w_u + x0 as usize;
        let i11 = y1 as usize * w_u + x1 as usize;

        let gx = (1.0 - fy) * ((1.0 - fx) * self.gx[i00] as f64 + fx * self.gx[i10] as f64)
            + fy * ((1.0 - fx) * self.gx[i01] as f64 + fx * self.gx[i11] as f64);
        let gy = (1.0 - fy) * ((1.0 - fx) * self.gy[i00] as f64 + fx * self.gy[i10] as f64)
            + fy * ((1.0 - fx) * self.gy[i01] as f64 + fx * self.gy[i11] as f64);
        (gx, gy)
    }
}

fn compute_sobel(img: &GrayImage) -> GradientField {
    let (w, h) = img.dimensions();
    let wu = w as usize;
    let hu = h as usize;
    let raw = img.as_raw();
    let mut gx = vec![0.0f32; wu * hu];
    let mut gy = vec![0.0f32; wu * hu];

    if wu >= 3 && hu >= 3 {
        for y in 1..(hu - 1) {
            let r0 = (y - 1) * wu;
            let r1 = y * wu;
            let r2 = (y + 1) * wu;
            for x in 1..(wu - 1) {
                let p00 = raw[r0 + x - 1] as f32;
                let p01 = raw[r0 + x] as f32;
                let p02 = raw[r0 + x + 1] as f32;
                let p10 = raw[r1 + x - 1] as f32;
                let p12 = raw[r1 + x + 1] as f32;
                let p20 = raw[r2 + x - 1] as f32;
                let p21 = raw[r2 + x] as f32;
                let p22 = raw[r2 + x + 1] as f32;

                gx[r1 + x] = ((-p00 + p02) + 2.0 * (-p10 + p12) + (-p20 + p22)) * 0.25;
                gy[r1 + x] = ((-p00 - 2.0 * p01 - p02) + (p20 + 2.0 * p21 + p22)) * 0.25;
            }
        }
    }

    GradientField { w, h, gx, gy }
}

fn merge_max_gradient(dst: &mut GradientField, other: &GradientField) {
    for i in 0..dst.gx.len() {
        let m1 = dst.gx[i] * dst.gx[i] + dst.gy[i] * dst.gy[i];
        let m2 = other.gx[i] * other.gx[i] + other.gy[i] * other.gy[i];
        if m2 > m1 {
            dst.gx[i] = other.gx[i];
            dst.gy[i] = other.gy[i];
        }
    }
}

fn rgb_to_gray(rgb: &RgbImage) -> GrayImage {
    let (w, h) = rgb.dimensions();
    let mut out = GrayImage::new(w, h);
    let src = rgb.as_raw();
    let dst = out.as_mut();
    for (i, chunk) in src.chunks_exact(3).enumerate() {
        let l = (77u32 * chunk[0] as u32 + 150u32 * chunk[1] as u32 + 29u32 * chunk[2] as u32 + 128) >> 8;
        dst[i] = l as u8;
    }
    out
}

/// Computes per-pixel Euclidean RGB distance to the median border (background) color.
fn rgb_border_distance_map(rgb: &RgbImage) -> GrayImage {
    let (w, h) = rgb.dimensions();
    let wu = w as usize;
    let hu = h as usize;
    let margin_x = ((w as f32 * 0.03).round() as usize).clamp(2, wu / 6);
    let margin_y = ((h as f32 * 0.03).round() as usize).clamp(2, hu / 6);
    let raw = rgb.as_raw();

    let mut hr = [0u32; 256];
    let mut hg = [0u32; 256];
    let mut hb = [0u32; 256];
    let mut count = 0u32;

    for y in 0..hu {
        let in_y_border = y < margin_y || y >= hu - margin_y;
        for x in 0..wu {
            if in_y_border || x < margin_x || x >= wu - margin_x {
                let idx = (y * wu + x) * 3;
                hr[raw[idx] as usize] += 1;
                hg[raw[idx + 1] as usize] += 1;
                hb[raw[idx + 2] as usize] += 1;
                count += 1;
            }
        }
    }

    let bg_r = hist_median(&hr, count) as f32;
    let bg_g = hist_median(&hg, count) as f32;
    let bg_b = hist_median(&hb, count) as f32;

    let mut out = GrayImage::new(w, h);
    let dst = out.as_mut();
    for (i, chunk) in raw.chunks_exact(3).enumerate() {
        let dr = chunk[0] as f32 - bg_r;
        let dg = chunk[1] as f32 - bg_g;
        let db = chunk[2] as f32 - bg_b;
        let dist = (dr * dr + dg * dg + db * db).sqrt() * 1.15;
        dst[i] = dist.clamp(0.0, 255.0) as u8;
    }
    out
}

fn hist_median(hist: &[u32; 256], total: u32) -> u8 {
    let half = total / 2;
    let mut acc = 0u32;
    for (v, &c) in hist.iter().enumerate() {
        acc += c;
        if acc >= half {
            return v as u8;
        }
    }
    128
}

/// Separable 2D L-infinity grayscale morphological closing: erode(dilate(img, r), r).
pub(crate) fn grayscale_dilate(img: &GrayImage, radius: usize) -> GrayImage {
    let (w, h) = img.dimensions();
    let wu = w as usize;
    let hu = h as usize;
    let src = img.as_raw();
    let mut tmp = vec![0u8; wu * hu];
    let mut out = GrayImage::new(w, h);
    let dst = out.as_mut();

    for y in 0..hu {
        let row = y * wu;
        for x in 0..wu {
            let x0 = x.saturating_sub(radius);
            let x1 = (x + radius).min(wu - 1);
            let mut m = 0u8;
            for xi in x0..=x1 {
                let v = src[row + xi];
                if v > m {
                    m = v;
                }
            }
            tmp[row + x] = m;
        }
    }
    for y in 0..hu {
        let y0 = y.saturating_sub(radius);
        let y1 = (y + radius).min(hu - 1);
        let dst_row = y * wu;
        for x in 0..wu {
            let mut m = 0u8;
            for yi in y0..=y1 {
                let v = tmp[yi * wu + x];
                if v > m {
                    m = v;
                }
            }
            dst[dst_row + x] = m;
        }
    }
    out
}

pub(crate) fn grayscale_close(img: &GrayImage, radius: usize) -> GrayImage {
    let dilated = grayscale_dilate(img, radius);
    let (w, h) = dilated.dimensions();
    let wu = w as usize;
    let hu = h as usize;
    let src = dilated.as_raw();
    let mut tmp = vec![0u8; wu * hu];
    let mut out = GrayImage::new(w, h);
    let dst = out.as_mut();

    for y in 0..hu {
        let row = y * wu;
        for x in 0..wu {
            let x0 = x.saturating_sub(radius);
            let x1 = (x + radius).min(wu - 1);
            let mut m = 255u8;
            for xi in x0..=x1 {
                let v = src[row + xi];
                if v < m {
                    m = v;
                }
            }
            tmp[row + x] = m;
        }
    }
    for y in 0..hu {
        let y0 = y.saturating_sub(radius);
        let y1 = (y + radius).min(hu - 1);
        let dst_row = y * wu;
        for x in 0..wu {
            let mut m = 255u8;
            for yi in y0..=y1 {
                let v = tmp[yi * wu + x];
                if v < m {
                    m = v;
                }
            }
            dst[dst_row + x] = m;
        }
    }
    out
}

fn otsu_masks(img: &GrayImage) -> Option<(GrayImage, GrayImage)> {
    let (w, h) = img.dimensions();
    let total = (w * h) as f64;
    if total < 256.0 {
        return None;
    }

    let mut hist = [0u32; 256];
    let mut sum_all = 0.0f64;
    for &p in img.as_raw() {
        hist[p as usize] += 1;
        sum_all += p as f64;
    }

    let mut w_b = 0.0f64;
    let mut sum_b = 0.0f64;
    let mut best_var = 0.0f64;
    let mut best_t = 128u8;

    for (t, &count) in hist.iter().enumerate() {
        w_b += count as f64;
        if w_b <= 0.0 {
            continue;
        }
        let w_f = total - w_b;
        if w_f <= 0.0 {
            break;
        }
        sum_b += (t as f64) * (count as f64);
        let m_b = sum_b / w_b;
        let m_f = (sum_all - sum_b) / w_f;
        let diff = m_b - m_f;
        let var = w_b * w_f * diff * diff;
        if var > best_var {
            best_var = var;
            best_t = t as u8;
        }
    }

    let between_std = (best_var / (total * total)).sqrt();
    if between_std < 8.0 {
        return None;
    }

    let mut bright = GrayImage::new(w, h);
    let mut dark = GrayImage::new(w, h);
    let src = img.as_raw();
    let b_raw = bright.as_mut();
    let d_raw = dark.as_mut();
    let wu = w as usize;
    let hu = h as usize;

    for y in 1..(hu - 1) {
        let row = y * wu;
        for x in 1..(wu - 1) {
            if src[row + x] > best_t {
                b_raw[row + x] = 255;
            } else {
                d_raw[row + x] = 255;
            }
        }
    }

    Some((bright, dark))
}

fn reduce_hull_to_quad(hull: &[(f64, f64)]) -> Option<Vec<(f64, f64)>> {
    if hull.len() < 4 {
        return None;
    }
    let mut poly = hull.to_vec();
    if poly.len() == 4 {
        return Some(poly);
    }
    if signed_polygon_area(&poly) < 0.0 {
        poly.reverse();
    }

    while poly.len() > 4 {
        let n = poly.len();
        let mut best_edge: Option<(usize, (f64, f64), f64)> = None;

        for i in 0..n {
            let p_prev = poly[(i + n - 1) % n];
            let p_a = poly[i];
            let p_b = poly[(i + 1) % n];
            let p_next = poly[(i + 2) % n];

            let d1 = (p_a.0 - p_prev.0, p_a.1 - p_prev.1);
            let d2 = (p_b.0 - p_next.0, p_b.1 - p_next.1);
            let denom = d1.0 * d2.1 - d1.1 * d2.0;
            if denom.abs() < 1e-6 {
                continue;
            }
            let rhs = (p_b.0 - p_a.0, p_b.1 - p_a.1);
            let t1 = (rhs.0 * d2.1 - rhs.1 * d2.0) / denom;
            let t2 = (rhs.0 * d1.1 - rhs.1 * d1.0) / denom;
            if t1 < -1e-4 || t2 < -1e-4 {
                continue;
            }
            let ix = p_a.0 + t1 * d1.0;
            let iy = p_a.1 + t1 * d1.1;
            let tri_area = 0.5 * ((p_b.0 - p_a.0) * (iy - p_a.1) - (p_b.1 - p_a.1) * (ix - p_a.0)).abs();

            if best_edge.is_none() || tri_area < best_edge.unwrap().2 {
                best_edge = Some((i, (ix, iy), tri_area));
            }
        }

        if let Some((idx, corner, _)) = best_edge {
            let next = (idx + 1) % n;
            poly[idx] = corner;
            poly.remove(next);
        } else {
            let mut min_v = 0;
            let mut min_a = f64::MAX;
            for i in 0..n {
                let prev = poly[(i + n - 1) % n];
                let curr = poly[i];
                let next = poly[(i + 1) % n];
                let a = 0.5 * ((curr.0 - prev.0) * (next.1 - prev.1) - (curr.1 - prev.1) * (next.0 - prev.0)).abs();
                if a < min_a {
                    min_a = a;
                    min_v = i;
                }
            }
            poly.remove(min_v);
        }
    }

    Some(poly)
}

fn line_from_points(a: (f64, f64), b: (f64, f64)) -> (f64, f64, f64) {
    let dx = b.0 - a.0;
    let dy = b.1 - a.1;
    let len = (dx * dx + dy * dy).sqrt().max(1e-9);
    let la = -dy / len;
    let lb = dx / len;
    let lc = -(la * a.0 + lb * a.1);
    (la, lb, lc)
}

fn fit_line_irls(pts: &[(f64, f64, f64)]) -> Option<(f64, f64, f64)> {
    let mut weights: Vec<f64> = pts.iter().map(|p| p.2.max(1.0)).collect();
    let mut line = (0.0f64, 0.0f64, 0.0f64);

    for iter in 0..3 {
        let mut w_sum = 0.0;
        let mut mx = 0.0;
        let mut my = 0.0;
        for (i, &(x, y, _)) in pts.iter().enumerate() {
            let w = weights[i];
            w_sum += w;
            mx += w * x;
            my += w * y;
        }
        if w_sum < 1e-6 {
            return None;
        }
        mx /= w_sum;
        my /= w_sum;

        let mut sxx = 0.0;
        let mut syy = 0.0;
        let mut sxy = 0.0;
        for (i, &(x, y, _)) in pts.iter().enumerate() {
            let w = weights[i];
            let dx = x - mx;
            let dy = y - my;
            sxx += w * dx * dx;
            syy += w * dy * dy;
            sxy += w * dx * dy;
        }

        let theta = 0.5 * (2.0 * sxy).atan2(sxx - syy);
        let nx = -theta.sin();
        let ny = theta.cos();
        let c = -(nx * mx + ny * my);
        line = (nx, ny, c);

        if iter < 2 {
            for (i, &(x, y, base_w)) in pts.iter().enumerate() {
                let err = (nx * x + ny * y + c).abs();
                weights[i] = base_w / (1.0 + (err / 1.5).powi(2));
            }
        }
    }

    Some(line)
}

fn intersect_lines(l1: (f64, f64, f64), l2: (f64, f64, f64)) -> Option<(f64, f64)> {
    let det = l1.0 * l2.1 - l2.0 * l1.1;
    if det.abs() < 1e-6 {
        return None;
    }
    let x = (l1.1 * l2.2 - l2.1 * l1.2) / det;
    let y = (l2.0 * l1.2 - l1.0 * l2.2) / det;
    Some((x, y))
}

fn within_frame_margin(pts: &[(f64, f64); 4], w: f64, h: f64, margin_frac: f64) -> bool {
    let mx = w * margin_frac;
    let my = h * margin_frac;
    pts.iter()
        .all(|p| p.0 >= -mx && p.0 <= w - 1.0 + mx && p.1 >= -my && p.1 <= h - 1.0 + my)
}

fn clamp_quad_to_frame(pts: [(f64, f64); 4], w: f64, h: f64) -> [(f64, f64); 4] {
    let max_x = (w - 1.0).max(0.0);
    let max_y = (h - 1.0).max(0.0);
    [
        (pts[0].0.clamp(0.0, max_x), pts[0].1.clamp(0.0, max_y)),
        (pts[1].0.clamp(0.0, max_x), pts[1].1.clamp(0.0, max_y)),
        (pts[2].0.clamp(0.0, max_x), pts[2].1.clamp(0.0, max_y)),
        (pts[3].0.clamp(0.0, max_x), pts[3].1.clamp(0.0, max_y)),
    ]
}

fn convex_hull_points(points: &[Point<i32>]) -> Vec<(f64, f64)> {
    let mut pts: Vec<(i64, i64)> = points.iter().map(|p| (p.x as i64, p.y as i64)).collect();
    pts.sort_unstable();
    pts.dedup();
    if pts.len() < 3 {
        return pts.into_iter().map(|(x, y)| (x as f64, y as f64)).collect();
    }

    let cross = |o: (i64, i64), a: (i64, i64), b: (i64, i64)| -> i64 {
        (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
    };

    let mut lower: Vec<(i64, i64)> = Vec::new();
    for &p in &pts {
        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0 {
            lower.pop();
        }
        lower.push(p);
    }

    let mut upper: Vec<(i64, i64)> = Vec::new();
    for &p in pts.iter().rev() {
        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0 {
            upper.pop();
        }
        upper.push(p);
    }

    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower.into_iter().map(|(x, y)| (x as f64, y as f64)).collect()
}

fn signed_polygon_area(pts: &[(f64, f64)]) -> f64 {
    if pts.len() < 3 {
        return 0.0;
    }
    let mut sum = 0.0;
    for i in 0..pts.len() {
        let j = (i + 1) % pts.len();
        sum += pts[i].0 * pts[j].1 - pts[j].0 * pts[i].1;
    }
    sum * 0.5
}

fn polygon_area(pts: &[(f64, f64)]) -> f64 {
    signed_polygon_area(pts).abs()
}

fn polygon_area_i32(pts: &[Point<i32>]) -> f64 {
    if pts.len() < 3 {
        return 0.0;
    }
    let mut sum = 0.0;
    for i in 0..pts.len() {
        let j = (i + 1) % pts.len();
        sum += (pts[i].x as f64) * (pts[j].y as f64) - (pts[j].x as f64) * (pts[i].y as f64);
    }
    sum.abs() * 0.5
}

fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

pub fn is_convex_quad(pts: &[(f64, f64)]) -> bool {
    if pts.len() != 4 {
        return false;
    }
    let mut sign = 0.0f64;
    for i in 0..4 {
        let a = pts[i];
        let b = pts[(i + 1) % 4];
        let c = pts[(i + 2) % 4];
        let cross = (b.0 - a.0) * (c.1 - b.1) - (b.1 - a.1) * (c.0 - b.0);
        if cross.abs() < 1e-6 {
            return false;
        }
        if sign == 0.0 {
            sign = cross;
        } else if sign * cross < 0.0 {
            return false;
        }
    }
    true
}

/// Order 4 points as Top-Left, Top-Right, Bottom-Right, Bottom-Left.
pub fn order_quad_points(pts: &[(f64, f64)]) -> [(f64, f64); 4] {
    let cx = pts.iter().map(|p| p.0).sum::<f64>() / 4.0;
    let cy = pts.iter().map(|p| p.1).sum::<f64>() / 4.0;

    let mut ordered = [pts[0], pts[1], pts[2], pts[3]];
    ordered.sort_by(|a, b| {
        let aa = (a.1 - cy).atan2(a.0 - cx);
        let ba = (b.1 - cy).atan2(b.0 - cx);
        aa.partial_cmp(&ba).unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut tl_idx = 0;
    let mut min_sum = f64::MAX;
    for (i, p) in ordered.iter().enumerate() {
        let s = p.0 + p.1;
        if s < min_sum {
            min_sum = s;
            tl_idx = i;
        }
    }

    let mut out = [(0.0, 0.0); 4];
    for i in 0..4 {
        out[i] = ordered[(tl_idx + i) % 4];
    }
    out
}

fn has_valid_document_geometry(ordered: &[(f64, f64); 4]) -> bool {
    let top = dist(ordered[0], ordered[1]);
    let right = dist(ordered[1], ordered[2]);
    let bottom = dist(ordered[2], ordered[3]);
    let left = dist(ordered[3], ordered[0]);
    let w = (top + bottom) * 0.5;
    let h = (left + right) * 0.5;
    if w < 12.0 || h < 12.0 || top.min(bottom) < 8.0 || left.min(right) < 8.0 {
        return false;
    }

    let ratio = w.max(h) / w.min(h);
    let opp_w = top.max(bottom) / top.min(bottom).max(1.0);
    let opp_h = left.max(right) / left.min(right).max(1.0);
    if ratio > 4.5 || opp_w > 2.6 || opp_h > 2.6 {
        return false;
    }

    for i in 0..4 {
        let prev = ordered[(i + 3) % 4];
        let curr = ordered[i];
        let next = ordered[(i + 1) % 4];
        let v1 = (prev.0 - curr.0, prev.1 - curr.1);
        let v2 = (next.0 - curr.0, next.1 - curr.1);
        let l1 = (v1.0 * v1.0 + v1.1 * v1.1).sqrt();
        let l2 = (v2.0 * v2.0 + v2.1 * v2.1).sqrt();
        if l1 < 1e-6 || l2 < 1e-6 {
            return false;
        }
        let cos_a = (v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2);
        if cos_a.abs() > 0.72 {
            return false;
        }
    }

    true
}
