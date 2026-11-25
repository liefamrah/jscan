use std::fs::{self, File};
use std::io::BufWriter;
use std::path::Path;

use image::{
    codecs::jpeg::JpegEncoder,
    imageops::{overlay, resize, rotate180, rotate270, rotate90, FilterType},
    ImageFormat, Rgb, RgbImage,
};

use crate::archive::create_zip_archive;
use crate::detect::{detect_corners_from_image_file, detect_corners_from_y_plane, open_oriented_image};
use crate::enhance::{apply_filter, stamp_watermark_rgb};
use crate::error::ScanError;
use crate::pdf::{build_pdf_from_images, merge_pdf_files, split_pdf_file};
use crate::warp::warp_perspective;

#[derive(Debug, Clone)]
pub struct Quad {
    /// Four normalized (0..1) corner points ordered: [TL, TR, BR, BL].
    pub pts: Vec<(f32, f32)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FilterKind {
    Original,
    Color,
    Grayscale,
    DocumentBw,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportImageFormat {
    Jpeg,
    Png,
}

#[derive(Debug, Clone)]
pub struct PageOut {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PdfFit {
    A4,
    Original,
}

#[derive(Debug, Clone)]
pub struct PdfOpts {
    pub fit: PdfFit,
    pub jpeg_quality: u8,
    pub margin_pt: f32,
    pub watermark_text: Option<String>,
}

#[derive(Debug, Clone)]
pub struct PageRange {
    pub start: u32,
    pub end: u32,
}

#[derive(Debug, Clone)]
pub struct ZipEntry {
    pub src_path: String,
    pub name_in_zip: String,
}

/// Live preview corner detection from a camera Y-plane (luma) frame.
/// Returns `None` when no confident document quad is detected.
pub fn detect_corners_live(
    y: Vec<u8>,
    width: u32,
    height: u32,
    row_stride: u32,
    rotation_deg: u32,
) -> Option<Quad> {
    detect_corners_from_y_plane(&y, width, height, row_stride, rotation_deg)
        .map(|pts| Quad { pts: pts.to_vec() })
}

/// Detect document corners from a full photo file.
/// Falls back to a 3% inset rectangle if no clear quad is found.
pub fn detect_corners_from_file(path: String) -> Result<Quad, ScanError> {
    let pts = detect_corners_from_image_file(&path)?;
    Ok(Quad { pts: pts.to_vec() })
}

/// Perspective-correct, enhance (with optional brightness/contrast in -1..1), rotate, and save as JPEG.
#[allow(clippy::too_many_arguments)]
pub fn process_page(
    src: String,
    dst: String,
    quad: Quad,
    filter: FilterKind,
    rotation_deg: u32,
    max_long_side: u32,
    jpeg_quality: u8,
    brightness: f32,
    contrast: f32,
) -> Result<PageOut, ScanError> {
    let pts_arr: [(f32, f32); 4] = quad.pts.try_into().map_err(|_| ScanError::InvalidQuad)?;
    let oriented = open_oriented_image(&src)?.to_rgb8();
    let warped = warp_perspective(&oriented, pts_arr, max_long_side)?;
    let enhanced = apply_filter(warped, filter, brightness, contrast);
    let final_img = apply_rotation(enhanced, rotation_deg);
    let (width, height) = final_img.dimensions();

    write_jpeg(&final_img, &dst, jpeg_quality)?;
    Ok(PageOut { width, height })
}

/// Compose front & back ID card images onto a single clean white A4 portrait sheet.
pub fn compose_id_card(
    front_src: String,
    back_src: String,
    dst: String,
    max_long_side: u32,
    jpeg_quality: u8,
) -> Result<PageOut, ScanError> {
    let front = open_oriented_image(&front_src)?.to_rgb8();
    let back = open_oriented_image(&back_src)?.to_rgb8();

    let page_h = max_long_side.clamp(800, 2480);
    let page_w = ((page_h as f32) * (595.28 / 841.89)).round() as u32;
    let mut canvas = RgbImage::from_pixel(page_w, page_h, Rgb([255, 255, 255]));

    let pad_x = (page_w as f32 * 0.14).round() as u32;
    let max_card_w = page_w.saturating_sub(pad_x * 2).max(64);
    let max_card_h = ((page_h as f32) * 0.34).round() as u32;

    let place = |canvas: &mut RgbImage, card: &RgbImage, center_y: u32| {
        let (cw, ch) = card.dimensions();
        let scale = (max_card_w as f32 / cw.max(1) as f32)
            .min(max_card_h as f32 / ch.max(1) as f32);
        let nw = ((cw as f32 * scale).round() as u32).max(16);
        let nh = ((ch as f32 * scale).round() as u32).max(16);
        let fitted = resize(card, nw, nh, FilterType::Triangle);

        let x0 = (page_w.saturating_sub(nw)) / 2;
        let y0 = center_y.saturating_sub(nh / 2);
        overlay(canvas, &fitted, x0 as i64, y0 as i64);

        // Subtle 1px light-gray border around each card.
        let border = Rgb([210, 214, 220]);
        for x in x0..(x0 + nw).min(page_w) {
            if y0 < page_h {
                canvas.put_pixel(x, y0, border);
            }
            if y0 + nh > 0 && y0 + nh - 1 < page_h {
                canvas.put_pixel(x, y0 + nh - 1, border);
            }
        }
        for y in y0..(y0 + nh).min(page_h) {
            if x0 < page_w {
                canvas.put_pixel(x0, y, border);
            }
            if x0 + nw > 0 && x0 + nw - 1 < page_w {
                canvas.put_pixel(x0 + nw - 1, y, border);
            }
        }
    };

    place(&mut canvas, &front, (page_h as f32 * 0.28).round() as u32);
    place(&mut canvas, &back, (page_h as f32 * 0.72).round() as u32);

    write_jpeg(&canvas, &dst, jpeg_quality)?;
    Ok(PageOut {
        width: page_w,
        height: page_h,
    })
}

/// Export an image to JPEG or PNG with optional downscaling and optional diagonal watermark.
pub fn export_image(
    src: String,
    dst: String,
    format: ExportImageFormat,
    max_long_side: u32,
    jpeg_quality: u8,
    watermark_text: Option<String>,
) -> Result<PageOut, ScanError> {
    let rgb = open_oriented_image(&src)?.to_rgb8();
    let (w, h) = rgb.dimensions();
    let cap = max_long_side.max(64);
    let long_side = w.max(h);
    let mut out_img = if long_side > cap {
        let scale = cap as f32 / long_side as f32;
        let nw = ((w as f32 * scale).round() as u32).max(1);
        let nh = ((h as f32 * scale).round() as u32).max(1);
        resize(&rgb, nw, nh, FilterType::Triangle)
    } else {
        rgb
    };
    if let Some(ref wm) = watermark_text {
        if !wm.trim().is_empty() {
            stamp_watermark_rgb(&mut out_img, wm);
        }
    }
    let (width, height) = out_img.dimensions();
    match format {
        ExportImageFormat::Jpeg => write_jpeg(&out_img, &dst, jpeg_quality)?,
        ExportImageFormat::Png => {
            ensure_parent_dir(&dst)?;
            out_img.save_with_format(&dst, ImageFormat::Png)?;
        }
    }
    Ok(PageOut { width, height })
}

/// Generate a lightweight JPEG thumbnail constrained to `max_side`.
pub fn make_thumbnail(src: String, dst: String, max_side: u32) -> Result<(), ScanError> {
    let rgb = open_oriented_image(&src)?.to_rgb8();
    let (w, h) = rgb.dimensions();
    let cap = max_side.max(32);
    let long_side = w.max(h);
    let thumb = if long_side > cap {
        let scale = cap as f32 / long_side as f32;
        let nw = ((w as f32 * scale).round() as u32).max(1);
        let nh = ((h as f32 * scale).round() as u32).max(1);
        resize(&rgb, nw, nh, FilterType::Triangle)
    } else {
        rgb
    };
    write_jpeg(&thumb, &dst, 78)
}

pub fn images_to_pdf(pages: Vec<String>, out: String, opts: PdfOpts) -> Result<(), ScanError> {
    build_pdf_from_images(&pages, &out, &opts)
}

pub fn merge_pdfs(inputs: Vec<String>, out: String) -> Result<(), ScanError> {
    merge_pdf_files(&inputs, &out)
}

pub fn split_pdf(
    input: String,
    out_dir: String,
    ranges: Vec<PageRange>,
) -> Result<Vec<String>, ScanError> {
    split_pdf_file(&input, &out_dir, &ranges)
}

pub fn zip_files(entries: Vec<ZipEntry>, out_zip: String) -> Result<(), ScanError> {
    create_zip_archive(&entries, &out_zip)
}

fn apply_rotation(img: RgbImage, rotation_deg: u32) -> RgbImage {
    match (rotation_deg % 360) / 90 * 90 {
        90 => rotate90(&img),
        180 => rotate180(&img),
        270 => rotate270(&img),
        _ => img,
    }
}

fn ensure_parent_dir(dst: &str) -> Result<(), ScanError> {
    if let Some(parent) = Path::new(dst).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}

fn write_jpeg(img: &RgbImage, dst: &str, quality: u8) -> Result<(), ScanError> {
    ensure_parent_dir(dst)?;
    let file = File::create(dst)?;
    let mut writer = BufWriter::new(file);
    let mut encoder = JpegEncoder::new_with_quality(&mut writer, quality.clamp(30, 100));
    encoder.encode_image(img)?;
    Ok(())
}
