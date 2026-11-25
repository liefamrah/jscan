use image::{
    imageops::{resize, FilterType},
    DynamicImage, GrayImage, Luma, Rgb, RgbImage,
};
use imageproc::{
    filter::{gaussian_blur_f32, median_filter},
    integral_image::{integral_image, integral_squared_image},
};

use crate::api::FilterKind;
use crate::detect::grayscale_close;

/// Apply the selected enhancement filter followed by optional brightness/contrast tuning.
/// `brightness` and `contrast` are normalized in `-1.0..=1.0` (`0.0` = neutral).
pub fn apply_filter(
    img: RgbImage,
    filter: FilterKind,
    brightness: f32,
    contrast: f32,
) -> RgbImage {
    let mut out = match filter {
        FilterKind::Original => img,
        FilterKind::Color => enhance_color(&img),
        FilterKind::Grayscale => enhance_grayscale(&img),
        FilterKind::DocumentBw => enhance_document_bw(&img),
    };
    if brightness.abs() > 0.005 || contrast.abs() > 0.005 {
        adjust_brightness_contrast_in_place(&mut out, brightness, contrast);
    }
    out
}

/// O(N) LUT adjustment for fine brightness (`-1..1`) and contrast (`-1..1`).
pub fn adjust_brightness_contrast_in_place(img: &mut RgbImage, brightness: f32, contrast: f32) {
    let b = brightness.clamp(-1.0, 1.0) * 64.0;
    let c = (1.0 + contrast.clamp(-1.0, 1.0) * 0.65).max(0.25);
    let mut lut = [0u8; 256];
    for (i, slot) in lut.iter_mut().enumerate() {
        let v = ((i as f32 - 128.0) * c + 128.0 + b).clamp(0.0, 255.0);
        *slot = v.round() as u8;
    }
    for byte in img.as_mut() {
        *byte = lut[*byte as usize];
    }
}

/// Stamp a subtle repeating diagonal text watermark onto an RGB image using a built-in 5x7 font.
pub fn stamp_watermark_rgb(img: &mut RgbImage, raw_text: &str) {
    let text: String = raw_text
        .trim()
        .to_ascii_uppercase()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == ' ' || *c == '-' || *c == '/' || *c == '.')
        .take(40)
        .collect();
    if text.is_empty() {
        return;
    }

    let (w, h) = img.dimensions();
    let long_side = w.max(h) as f32;
    let scale = (long_side / 420.0).clamp(2.0, 8.0);
    let char_adv = 6.0 * scale;
    let text_w = text.len() as f32 * char_adv;
    let text_h = 7.0 * scale;

    // Draw at 3 diagonal positions (upper, center, lower) rotated -28 degrees.
    let angle: f32 = -28.0_f32.to_radians();
    let cos_a = angle.cos();
    let sin_a = angle.sin();
    let centers = [
        (w as f32 * 0.5, h as f32 * 0.24),
        (w as f32 * 0.5, h as f32 * 0.52),
        (w as f32 * 0.5, h as f32 * 0.80),
    ];

    let step = (scale.round() as i32).max(1);
    for (cx, cy) in centers {
        for (ci, ch) in text.chars().enumerate() {
            let glyph = glyph_5x7(ch);
            for (row, &bits) in glyph.iter().enumerate() {
                for col in 0..5 {
                    if (bits >> (4 - col)) & 1 == 0 {
                        continue;
                    }
                    let lx = ci as f32 * char_adv + col as f32 * scale - text_w * 0.5;
                    let ly = row as f32 * scale - text_h * 0.5;
                    let rx = cx + lx * cos_a - ly * sin_a;
                    let ry = cy + lx * sin_a + ly * cos_a;
                    let px = rx.round() as i32;
                    let py = ry.round() as i32;
                    for dy in 0..step {
                        for dx in 0..step {
                            let x = px + dx;
                            let y = py + dy;
                            if x >= 0 && y >= 0 && (x as u32) < w && (y as u32) < h {
                                let p = img.get_pixel_mut(x as u32, y as u32);
                                // Blend with cool slate gray at 28% opacity.
                                p[0] = ((p[0] as f32 * 0.72) + (90.0 * 0.28)) as u8;
                                p[1] = ((p[1] as f32 * 0.72) + (100.0 * 0.28)) as u8;
                                p[2] = ((p[2] as f32 * 0.72) + (120.0 * 0.28)) as u8;
                            }
                        }
                    }
                }
            }
        }
    }
}

fn glyph_5x7(c: char) -> [u8; 7] {
    match c {
        'A' => [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'B' => [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        'C' => [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        'D' => [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
        'E' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        'F' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        'G' => [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'I' => [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        'J' => [0x07, 0x02, 0x02, 0x02, 0x12, 0x12, 0x0C],
        'K' => [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        'M' => [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        'N' => [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
        'O' => [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'P' => [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        'Q' => [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        'R' => [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        'S' => [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        'T' => [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        'U' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'V' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        'W' => [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
        'X' => [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        'Y' => [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
        'Z' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        '0' => [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        '1' => [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        '2' => [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        '3' => [0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E],
        '4' => [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        '5' => [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        '6' => [0x0E, 0x10, 0x1E, 0x11, 0x11, 0x11, 0x0E],
        '7' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        '8' => [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        '9' => [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        '-' => [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        '/' => [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10],
        '.' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        _ => [0x00; 7],
    }
}

/// Estimate local paper illumination at 1/8 scale using morphological closing (erases dark text
/// and logos while keeping sharp phone/hand shadow boundaries unshifted) + gentle Gaussian blur.
fn estimate_background_1_8(small: &GrayImage, full_w: u32, full_h: u32) -> GrayImage {
    let (sw, sh) = small.dimensions();
    let long_s = sw.max(sh) as f32;
    let close_r = ((long_s * 0.032).round() as usize).clamp(4, 9);
    let closed = grayscale_close(small, close_r);
    let sigma = (long_s * 0.018).clamp(1.5, 4.5);
    let bg_small = gaussian_blur_f32(&closed, sigma);
    resize(&bg_small, full_w, full_h, FilterType::Triangle)
}

/// Remove uneven lighting/shadows by dividing each channel by its morphological illumination map.
fn remove_shadow_gray(gray: &GrayImage) -> GrayImage {
    let (w, h) = gray.dimensions();
    let sw = (w / 8).max(8);
    let sh = (h / 8).max(8);
    let small = resize(gray, sw, sh, FilterType::Triangle);
    let bg = estimate_background_1_8(&small, w, h);

    let mut out = GrayImage::new(w, h);
    let src_raw = gray.as_raw();
    let bg_raw = bg.as_raw();
    let out_raw = out.as_mut();
    for i in 0..src_raw.len() {
        let b = (bg_raw[i] as f32).max(20.0);
        let v = ((src_raw[i] as f32 / b) * 255.0).clamp(0.0, 255.0);
        out_raw[i] = v as u8;
    }
    out
}

fn remove_shadow_rgb(img: &RgbImage) -> RgbImage {
    let (w, h) = img.dimensions();
    let sw = (w / 8).max(8);
    let sh = (h / 8).max(8);
    let small = resize(img, sw, sh, FilterType::Triangle);

    let mut ch = [
        GrayImage::new(sw, sh),
        GrayImage::new(sw, sh),
        GrayImage::new(sw, sh),
    ];
    for (i, px) in small.pixels().enumerate() {
        ch[0].as_mut()[i] = px[0];
        ch[1].as_mut()[i] = px[1];
        ch[2].as_mut()[i] = px[2];
    }

    let bg_r = estimate_background_1_8(&ch[0], w, h);
    let bg_g = estimate_background_1_8(&ch[1], w, h);
    let bg_b = estimate_background_1_8(&ch[2], w, h);

    let mut out = RgbImage::new(w, h);
    let src_raw = img.as_raw();
    let out_raw = out.as_mut();
    let br = bg_r.as_raw();
    let bg = bg_g.as_raw();
    let bb = bg_b.as_raw();

    for i in 0..(w as usize * h as usize) {
        let base = i * 3;
        out_raw[base] =
            ((src_raw[base] as f32 / (br[i] as f32).max(20.0)) * 255.0).clamp(0.0, 255.0) as u8;
        out_raw[base + 1] =
            ((src_raw[base + 1] as f32 / (bg[i] as f32).max(20.0)) * 255.0).clamp(0.0, 255.0) as u8;
        out_raw[base + 2] =
            ((src_raw[base + 2] as f32 / (bb[i] as f32).max(20.0)) * 255.0).clamp(0.0, 255.0) as u8;
    }
    out
}

fn percentile_bounds(hist: &[u32; 256], total: u32, low_pct: f32, high_pct: f32) -> (u8, u8) {
    let low_target = (total as f32 * low_pct) as u32;
    let high_target = (total as f32 * high_pct) as u32;
    let mut lo = 0u8;
    let mut hi = 255u8;
    let mut acc = 0u32;
    let mut found_lo = false;
    for (v, &c) in hist.iter().enumerate() {
        acc += c;
        if !found_lo && acc >= low_target {
            lo = v as u8;
            found_lo = true;
        }
        if acc >= high_target {
            hi = v as u8;
            break;
        }
    }
    if hi <= lo {
        (0, 255)
    } else {
        (lo, hi)
    }
}

fn stretch_gray_in_place(gray: &mut GrayImage) {
    let mut hist = [0u32; 256];
    for &p in gray.as_raw() {
        hist[p as usize] += 1;
    }
    let total = gray.width() * gray.height();
    let (lo, hi) = percentile_bounds(&hist, total, 0.01, 0.99);
    let span = (hi - lo) as f32;
    if span < 1.0 {
        return;
    }
    let mut lut = [0u8; 256];
    for (i, slot) in lut.iter_mut().enumerate() {
        let v = (((i as f32 - lo as f32) / span) * 255.0).clamp(0.0, 255.0);
        *slot = v as u8;
    }
    for p in gray.as_mut() {
        *p = lut[*p as usize];
    }
}

fn enhance_color(img: &RgbImage) -> RgbImage {
    let mut balanced = remove_shadow_rgb(img);
    let (w, h) = balanced.dimensions();
    let total = w * h;

    let mut hists = [[0u32; 256]; 3];
    for chunk in balanced.as_raw().chunks_exact(3) {
        hists[0][chunk[0] as usize] += 1;
        hists[1][chunk[1] as usize] += 1;
        hists[2][chunk[2] as usize] += 1;
    }

    let mut luts = [[0u8; 256]; 3];
    for c in 0..3 {
        let (lo, hi) = percentile_bounds(&hists[c], total, 0.015, 0.94);
        let span = (hi - lo) as f32;
        for i in 0..256 {
            luts[c][i] = if span < 1.0 {
                i as u8
            } else {
                let norm = ((i as f32 - lo as f32) / span).clamp(0.0, 1.0);
                // Crisp white paper cleanup while preserving text and logo saturation.
                let v = if norm > 0.92 { 1.0 } else { norm / 0.92 };
                (v * 255.0).clamp(0.0, 255.0) as u8
            };
        }
    }

    for chunk in balanced.as_mut().chunks_exact_mut(3) {
        chunk[0] = luts[0][chunk[0] as usize];
        chunk[1] = luts[1][chunk[1] as usize];
        chunk[2] = luts[2][chunk[2] as usize];
    }

    mild_sharpen_rgb(&balanced)
}

fn mild_sharpen_rgb(img: &RgbImage) -> RgbImage {
    let (w, h) = img.dimensions();
    if w < 3 || h < 3 {
        return img.clone();
    }
    let mut out = img.clone();
    let src = img.as_raw();
    let dst = out.as_mut();
    let stride = (w as usize) * 3;
    for y in 1..(h as usize - 1) {
        for x in 1..(w as usize - 1) {
            let idx = y * stride + x * 3;
            for c in 0..3 {
                let center = src[idx + c] as f32;
                let neighbors = src[idx - stride + c] as f32
                    + src[idx + stride + c] as f32
                    + src[idx - 3 + c] as f32
                    + src[idx + 3 + c] as f32;
                let v = (center * 1.4 - neighbors * 0.1).clamp(0.0, 255.0);
                dst[idx + c] = v as u8;
            }
        }
    }
    out
}

fn enhance_grayscale(img: &RgbImage) -> RgbImage {
    let gray = DynamicImage::ImageRgb8(img.clone()).to_luma8();
    let mut flat = remove_shadow_gray(&gray);
    stretch_gray_in_place(&mut flat);
    gray_to_rgb(&flat)
}

fn enhance_document_bw(img: &RgbImage) -> RgbImage {
    let gray = DynamicImage::ImageRgb8(img.clone()).to_luma8();
    let flat = remove_shadow_gray(&gray);
    let clean = median_filter(&flat, 1, 1);
    let bw = sauvola_binarize(&clean, 0.2);
    let despeckled = despeckle_binary(&bw);
    gray_to_rgb(&despeckled)
}

/// O(N) Sauvola adaptive binarization using integral and integral-squared images.
pub fn sauvola_binarize(gray: &GrayImage, k: f64) -> GrayImage {
    let (w, h) = gray.dimensions();
    if w == 0 || h == 0 {
        return gray.clone();
    }
    let long_side = w.max(h) as f64;
    let mut win = ((25.0 * long_side / 1500.0).round() as i32).clamp(11, 51);
    if win % 2 == 0 {
        win += 1;
    }
    let r = win / 2;

    let integ = integral_image::<_, u64>(gray);
    let integ_sq = integral_squared_image(gray);

    let mut out = GrayImage::new(w, h);
    let w_i = w as i32;
    let h_i = h as i32;
    let r_dyn = 128.0f64;

    for y in 0..h_i {
        let y1 = (y - r).max(0) as u32;
        let y2 = (y + r).min(h_i - 1) as u32;
        for x in 0..w_i {
            let x1 = (x - r).max(0) as u32;
            let x2 = (x + r).min(w_i - 1) as u32;

            let area = ((x2 - x1 + 1) * (y2 - y1 + 1)) as f64;
            let sum = rect_sum(&integ, x1, y1, x2, y2) as f64;
            let sq_sum = rect_sum(&integ_sq, x1, y1, x2, y2) as f64;

            let mean = sum / area;
            let variance = ((sq_sum / area) - mean * mean).max(0.0);
            let std_dev = variance.sqrt();
            let threshold = mean * (1.0 + k * ((std_dev / r_dyn) - 1.0));

            let px = gray.get_pixel(x as u32, y as u32)[0] as f64;
            let bin = if px < threshold { 0u8 } else { 255u8 };
            out.put_pixel(x as u32, y as u32, Luma([bin]));
        }
    }
    out
}

#[inline]
fn rect_sum(
    integ: &image::ImageBuffer<Luma<u64>, Vec<u64>>,
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
) -> u64 {
    let a = integ.get_pixel(x1, y1)[0];
    let b = integ.get_pixel(x2 + 1, y1)[0];
    let c = integ.get_pixel(x1, y2 + 1)[0];
    let d = integ.get_pixel(x2 + 1, y2 + 1)[0];
    d + a - b - c
}

fn despeckle_binary(bw: &GrayImage) -> GrayImage {
    let (w, h) = bw.dimensions();
    if w < 3 || h < 3 {
        return bw.clone();
    }
    let mut out = bw.clone();
    let src = bw.as_raw();
    let dst = out.as_mut();
    let wu = w as usize;

    for y in 1..(h as usize - 1) {
        let row = y * wu;
        for x in 1..(wu - 1) {
            let idx = row + x;
            if src[idx] == 0 {
                let mut black_neighbors = 0u8;
                for dy in [-1isize, 0, 1] {
                    let nr = (y as isize + dy) as usize * wu;
                    for dx in [-1isize, 0, 1] {
                        if dx == 0 && dy == 0 {
                            continue;
                        }
                        if src[nr + (x as isize + dx) as usize] == 0 {
                            black_neighbors += 1;
                        }
                    }
                }
                if black_neighbors <= 1 {
                    dst[idx] = 255;
                }
            }
        }
    }
    out
}

fn gray_to_rgb(gray: &GrayImage) -> RgbImage {
    let (w, h) = gray.dimensions();
    let mut out = RgbImage::new(w, h);
    for (p, dst) in gray.as_raw().iter().zip(out.pixels_mut()) {
        *dst = Rgb([*p, *p, *p]);
    }
    out
}
