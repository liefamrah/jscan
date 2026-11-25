use image::{
    imageops::{crop_imm, resize, FilterType},
    RgbImage,
};
use imageproc::geometric_transformations::{warp_into_with, Border, Interpolation};

use crate::detect::{is_convex_quad, order_quad_points};
use crate::error::ScanError;

/// Perspective-correct an RGB image given normalized quad coordinates [TL, TR, BR, BL].
/// Uses Zhang & He projective aspect-ratio recovery, exact f64 square-to-quad homography,
/// bicubic interpolation, and edge replication. Falls back to bounding-box crop if degenerate.
pub fn warp_perspective(
    img: &RgbImage,
    quad_norm: [(f32, f32); 4],
    max_long_side: u32,
) -> Result<RgbImage, ScanError> {
    let (w, h) = img.dimensions();
    if w == 0 || h == 0 {
        return Err(ScanError::InvalidArgument("Empty image".into()));
    }
    for (x, y) in quad_norm {
        if !x.is_finite() || !y.is_finite() {
            return Err(ScanError::InvalidQuad);
        }
    }

    let max_x = (w - 1) as f64;
    let max_y = (h - 1) as f64;
    let raw_src: [(f64, f64); 4] = [
        (quad_norm[0].0.clamp(0.0, 1.0) as f64 * max_x, quad_norm[0].1.clamp(0.0, 1.0) as f64 * max_y),
        (quad_norm[1].0.clamp(0.0, 1.0) as f64 * max_x, quad_norm[1].1.clamp(0.0, 1.0) as f64 * max_y),
        (quad_norm[2].0.clamp(0.0, 1.0) as f64 * max_x, quad_norm[2].1.clamp(0.0, 1.0) as f64 * max_y),
        (quad_norm[3].0.clamp(0.0, 1.0) as f64 * max_x, quad_norm[3].1.clamp(0.0, 1.0) as f64 * max_y),
    ];

    // Guarantee a valid clockwise [TL, TR, BR, BL] convex quad before solving homography.
    let src = if is_convex_quad(&raw_src) && signed_quad_area(&raw_src) > 0.0 {
        raw_src
    } else {
        let reordered = order_quad_points(&raw_src);
        if is_convex_quad(&reordered) {
            reordered
        } else {
            return Ok(bounding_box_fallback(img, raw_src, max_long_side));
        }
    };

    let top = hypot(src[0], src[1]);
    let bottom = hypot(src[3], src[2]);
    let left = hypot(src[0], src[3]);
    let right = hypot(src[1], src[2]);

    // +1.0 converts pixel-center span (e.g. 0..399) back to inclusive pixel count (400).
    let max_w = top.max(bottom) + 1.0;
    let max_h = left.max(right) + 1.0;

    if max_w < 8.0 || max_h < 8.0 {
        return Ok(bounding_box_fallback(img, src, max_long_side));
    }

    let aspect = estimate_rect_aspect_ratio(src, w as f64, h as f64, max_w / max_h);
    let (raw_w, raw_h) = if aspect >= max_w / max_h {
        (max_h * aspect, max_h)
    } else {
        (max_w, max_w / aspect)
    };

    let cap = max_long_side.max(64) as f64;
    let long_side = raw_w.max(raw_h);
    let scale = if long_side > cap { cap / long_side } else { 1.0 };

    let out_w = ((raw_w * scale).round() as u32).max(16);
    let out_h = ((raw_h * scale).round() as u32).max(16);

    let Some(hom) = SquareToQuadHomography::from_quad(src) else {
        return Ok(bounding_box_fallback(img, src, max_long_side));
    };

    let inv_w = 1.0 / (out_w - 1).max(1) as f64;
    let inv_h = 1.0 / (out_h - 1).max(1) as f64;

    let mut out = RgbImage::new(out_w, out_h);
    warp_into_with(
        img,
        move |x, y| {
            let u = x as f64 * inv_w;
            let v = y as f64 * inv_h;
            hom.map(u, v)
        },
        Interpolation::Bicubic,
        Border::Replicate,
        &mut out,
    );
    Ok(out)
}

/// Exact closed-form f64 projective mapping from unit square [0, 1]^2 to quad [TL, TR, BR, BL]
/// (Heckbert 1989). Avoids f32 matrix inversion errors on high-resolution camera photos.
#[derive(Clone, Copy)]
struct SquareToQuadHomography {
    a: f64,
    b: f64,
    c: f64,
    d: f64,
    e: f64,
    f: f64,
    g: f64,
    h: f64,
}

impl SquareToQuadHomography {
    fn from_quad(src: [(f64, f64); 4]) -> Option<Self> {
        let (x0, y0) = src[0];
        let (x1, y1) = src[1];
        let (x2, y2) = src[2];
        let (x3, y3) = src[3];

        let dx1 = x1 - x2;
        let dx2 = x3 - x2;
        let sx = x0 - x1 + x2 - x3;
        let dy1 = y1 - y2;
        let dy2 = y3 - y2;
        let sy = y0 - y1 + y2 - y3;

        let det = dx1 * dy2 - dx2 * dy1;
        if det.abs() < 1e-12 {
            return None;
        }

        let g = (sx * dy2 - sy * dx2) / det;
        let h = (dx1 * sy - dy1 * sx) / det;

        // Denominator must stay strictly positive over all 4 corners of [0, 1]^2.
        if 1.0 + g <= 1e-6 || 1.0 + h <= 1e-6 || 1.0 + g + h <= 1e-6 {
            return None;
        }

        let a = x1 - x0 + g * x1;
        let b = x3 - x0 + h * x3;
        let c = x0;
        let d = y1 - y0 + g * y1;
        let e = y3 - y0 + h * y3;
        let f = y0;

        Some(Self { a, b, c, d, e, f, g, h })
    }

    #[inline(always)]
    fn map(&self, u: f64, v: f64) -> (f32, f32) {
        let denom = self.g * u + self.h * v + 1.0;
        let sx = (self.a * u + self.b * v + self.c) / denom;
        let sy = (self.d * u + self.e * v + self.f) / denom;
        (sx as f32, sy as f32)
    }
}

/// Recover true physical aspect ratio (W / H) of a planar rectangle from its 4 projected corners
/// (Zhang & He closed-form projective geometry using principal point at image center).
fn estimate_rect_aspect_ratio(
    src: [(f64, f64); 4],
    img_w: f64,
    img_h: f64,
    naive_aspect: f64,
) -> f64 {
    let u0 = (img_w - 1.0) * 0.5;
    let v0 = (img_h - 1.0) * 0.5;

    // Zhang & He vertex convention: m1 = TL, m2 = TR, m3 = BL, m4 = BR.
    let m1 = (src[0].0 - u0, src[0].1 - v0, 1.0);
    let m2 = (src[1].0 - u0, src[1].1 - v0, 1.0);
    let m3 = (src[3].0 - u0, src[3].1 - v0, 1.0);
    let m4 = (src[2].0 - u0, src[2].1 - v0, 1.0);

    let m1xm4 = cross3(m1, m4);
    let denom2 = dot3(cross3(m2, m4), m3);
    let denom3 = dot3(cross3(m3, m4), m2);
    if denom2.abs() < 1e-9 || denom3.abs() < 1e-9 {
        return naive_aspect;
    }

    let k2 = dot3(m1xm4, m3) / denom2;
    let k3 = dot3(m1xm4, m2) / denom3;
    if !k2.is_finite() || !k3.is_finite() || k2 <= 0.1 || k3 <= 0.1 || k2 > 10.0 || k3 > 10.0 {
        return naive_aspect;
    }

    let n2 = (k2 * m2.0 - m1.0, k2 * m2.1 - m1.1, k2 - 1.0);
    let n3 = (k3 * m3.0 - m1.0, k3 * m3.1 - m1.1, k3 - 1.0);

    // If nearly fronto-parallel (minimal perspective tilt), naive ratio is already exact.
    if n2.2.abs() < 0.015 && n3.2.abs() < 0.015 {
        return naive_aspect;
    }

    let diag = (img_w * img_w + img_h * img_h).sqrt();
    // Typical smartphone main camera (~26mm eq, ~65 deg FOV) has f ~= 0.85 * image diagonal.
    let f_default = 0.85 * diag;
    let f_sq = if n2.2.abs() > 0.025 && n3.2.abs() > 0.025 {
        let est = -(n2.0 * n3.0 + n2.1 * n3.1) / (n2.2 * n3.2);
        let min_f2 = (0.45 * diag).powi(2);
        let max_f2 = (2.5 * diag).powi(2);
        if est.is_finite() && est >= min_f2 && est <= max_f2 {
            est
        } else {
            f_default * f_default
        }
    } else {
        f_default * f_default
    };

    let w_sq = n2.0 * n2.0 + n2.1 * n2.1 + f_sq * n2.2 * n2.2;
    let h_sq = n3.0 * n3.0 + n3.1 * n3.1 + f_sq * n3.2 * n3.2;
    if w_sq <= 1e-6 || h_sq <= 1e-6 {
        return naive_aspect;
    }

    let aspect = (w_sq / h_sq).sqrt();
    if !aspect.is_finite() {
        return naive_aspect;
    }

    // Clamp gently relative to naive ratio so extreme manual drags never produce slivers.
    aspect
        .clamp(naive_aspect * 0.5, naive_aspect * 2.0)
        .clamp(0.2, 5.0)
}

#[inline]
fn cross3(a: (f64, f64, f64), b: (f64, f64, f64)) -> (f64, f64, f64) {
    (
        a.1 * b.2 - a.2 * b.1,
        a.2 * b.0 - a.0 * b.2,
        a.0 * b.1 - a.1 * b.0,
    )
}

#[inline]
fn dot3(a: (f64, f64, f64), b: (f64, f64, f64)) -> f64 {
    a.0 * b.0 + a.1 * b.1 + a.2 * b.2
}

fn signed_quad_area(pts: &[(f64, f64); 4]) -> f64 {
    let mut sum = 0.0;
    for i in 0..4 {
        let j = (i + 1) % 4;
        sum += pts[i].0 * pts[j].1 - pts[j].0 * pts[i].1;
    }
    sum * 0.5
}

fn hypot(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

fn bounding_box_fallback(img: &RgbImage, src: [(f64, f64); 4], max_long_side: u32) -> RgbImage {
    let (w, h) = img.dimensions();
    let min_x = src.iter().map(|p| p.0).fold(f64::INFINITY, f64::min).floor().max(0.0) as u32;
    let min_y = src.iter().map(|p| p.1).fold(f64::INFINITY, f64::min).floor().max(0.0) as u32;
    let max_x = src.iter().map(|p| p.0).fold(0.0f64, f64::max).ceil().min(w as f64) as u32;
    let max_y = src.iter().map(|p| p.1).fold(0.0f64, f64::max).ceil().min(h as f64) as u32;

    let cw = max_x.saturating_sub(min_x);
    let ch = max_y.saturating_sub(min_y);
    let cropped = if cw >= 8 && ch >= 8 {
        crop_imm(img, min_x, min_y, cw, ch).to_image()
    } else {
        img.clone()
    };

    let (rw, rh) = cropped.dimensions();
    let long_side = rw.max(rh);
    let cap = max_long_side.max(64);
    if long_side > cap {
        let scale = cap as f32 / long_side as f32;
        let nw = ((rw as f32 * scale).round() as u32).max(1);
        let nh = ((rh as f32 * scale).round() as u32).max(1);
        resize(&cropped, nw, nh, FilterType::Triangle)
    } else {
        cropped
    }
}
