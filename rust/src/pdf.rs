use std::collections::BTreeMap;
use std::fs;
use std::io::Cursor;
use std::path::Path;

use image::codecs::jpeg::JpegEncoder;
use lopdf::{dictionary, Document, Object, ObjectId, Stream};

use crate::api::{PageRange, PdfFit, PdfOpts};
use crate::detect::open_oriented_image;
use crate::error::ScanError;

const A4_WIDTH_PT: f32 = 595.28;
const A4_HEIGHT_PT: f32 = 841.89;

/// Build a multi-page PDF from image files.
/// Already-JPEG files are embedded directly as `DCTDecode` streams without re-encoding.
pub fn build_pdf_from_images(
    pages: &[String],
    out_path: &str,
    opts: &PdfOpts,
) -> Result<(), ScanError> {
    if pages.is_empty() {
        return Err(ScanError::InvalidArgument("No pages provided".into()));
    }

    let mut doc = Document::with_version("1.5");
    let pages_id = doc.new_object_id();
    let mut page_ids: Vec<Object> = Vec::with_capacity(pages.len());

    let watermark = opts
        .watermark_text
        .as_deref()
        .map(sanitize_pdf_ascii)
        .filter(|s| !s.is_empty());

    let (wm_font_id, wm_gs_id) = if watermark.is_some() {
        let font_id = doc.add_object(dictionary! {
            "Type" => "Font",
            "Subtype" => "Type1",
            "BaseFont" => "Helvetica-Bold",
        });
        let gs_id = doc.add_object(dictionary! {
            "Type" => "ExtGState",
            "ca" => 0.22_f32,
            "CA" => 0.22_f32,
        });
        (Some(font_id), Some(gs_id))
    } else {
        (None, None)
    };

    let margin = opts.margin_pt.clamp(0.0, 72.0);

    for (idx, page_path) in pages.iter().enumerate() {
        let (jpeg_bytes, img_w, img_h, color_space) = load_as_jpeg_stream(page_path, opts.jpeg_quality)?;
        let (page_w, page_h, draw_x, draw_y, draw_w, draw_h) = match opts.fit {
            PdfFit::A4 => {
                // Fit image centered inside A4 (auto landscape if image is wider than tall).
                let (pw, ph) = if img_w > img_h {
                    (A4_HEIGHT_PT, A4_WIDTH_PT)
                } else {
                    (A4_WIDTH_PT, A4_HEIGHT_PT)
                };
                let avail_w = (pw - margin * 2.0).max(72.0);
                let avail_h = (ph - margin * 2.0).max(72.0);
                let scale = (avail_w / img_w as f32).min(avail_h / img_h as f32);
                let dw = img_w as f32 * scale;
                let dh = img_h as f32 * scale;
                let dx = (pw - dw) * 0.5;
                let dy = (ph - dh) * 0.5;
                (pw, ph, dx, dy, dw, dh)
            }
            PdfFit::Original => {
                // Pixel dimensions interpreted at 150 DPI -> PDF points (72 pt/inch).
                let pw = img_w as f32 * 72.0 / 150.0;
                let ph = img_h as f32 * 72.0 / 150.0;
                (pw, ph, 0.0, 0.0, pw, ph)
            }
        };

        let img_name = format!("Im{}", idx + 1);
        let img_stream = Stream::new(
            dictionary! {
                "Type" => "XObject",
                "Subtype" => "Image",
                "Width" => img_w as i64,
                "Height" => img_h as i64,
                "ColorSpace" => color_space,
                "BitsPerComponent" => 8,
                "Filter" => "DCTDecode",
            },
            jpeg_bytes,
        );
        let img_id = doc.add_object(Object::Stream(img_stream));

        let mut content_ops = format!(
            "q\n{:.2} 0 0 {:.2} {:.2} {:.2} cm\n/{} Do\nQ\n",
            draw_w, draw_h, draw_x, draw_y, img_name
        );

        if let Some(ref wm) = watermark {
            let font_size = (page_w.min(page_h) * 0.055).clamp(16.0, 38.0);
            // Draw 3 subtle diagonal watermark bands across the page.
            let cos_a = 0.866_f32;
            let sin_a = 0.5_f32;
            let est_width = wm.len() as f32 * font_size * 0.56;
            for frac in [0.24_f32, 0.52_f32, 0.80_f32] {
                let cx = page_w * 0.5 - (est_width * 0.5 * cos_a);
                let cy = page_h * frac - (est_width * 0.5 * sin_a);
                content_ops.push_str(&format!(
                    "q\n/GS1 gs\n0.30 0.35 0.45 rg\nBT\n/F1 {:.1} Tf\n{:.3} {:.3} {:.3} {:.3} {:.2} {:.2} Tm\n({}) Tj\nET\nQ\n",
                    font_size, cos_a, sin_a, -sin_a, cos_a, cx, cy, wm
                ));
            }
        }

        let content_id = doc.add_object(Object::Stream(Stream::new(
            dictionary! {},
            content_ops.into_bytes(),
        )));

        let mut resources = dictionary! {
            "XObject" => dictionary! {
                img_name => img_id,
            },
        };
        if let (Some(fid), Some(gid)) = (wm_font_id, wm_gs_id) {
            resources.set("Font", dictionary! { "F1" => fid });
            resources.set("ExtGState", dictionary! { "GS1" => gid });
        }

        let page_id = doc.add_object(dictionary! {
            "Type" => "Page",
            "Parent" => pages_id,
            "MediaBox" => vec![0.into(), 0.into(), page_w.into(), page_h.into()],
            "Resources" => resources,
            "Contents" => content_id,
        });
        page_ids.push(page_id.into());
    }

    doc.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => page_ids,
            "Count" => pages.len() as i64,
        }),
    );

    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);

    if let Some(parent) = Path::new(out_path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    doc.save(out_path)?;
    Ok(())
}

/// Merge multiple PDF files in order while preserving page order and resources.
pub fn merge_pdf_files(inputs: &[String], out_path: &str) -> Result<(), ScanError> {
    if inputs.len() < 2 {
        return Err(ScanError::InvalidArgument(
            "At least 2 PDF files are required to merge".into(),
        ));
    }

    let mut max_id: u32 = 1;
    let mut documents_pages: BTreeMap<ObjectId, Object> = BTreeMap::new();
    let mut documents_objects: BTreeMap<ObjectId, Object> = BTreeMap::new();
    let mut merged = Document::with_version("1.5");

    for input in inputs {
        let mut doc = Document::load(input)?;
        if doc.is_encrypted() {
            return Err(ScanError::EncryptedPdf);
        }
        doc.renumber_objects_with(max_id);
        max_id = doc.max_id + 1;

        for (_, page_id) in doc.get_pages() {
            if let Ok(obj) = doc.get_object(page_id) {
                documents_pages.insert(page_id, obj.to_owned());
            }
        }
        documents_objects.extend(doc.objects);
    }

    if documents_pages.is_empty() {
        return Err(ScanError::Pdf("No pages found in input PDFs".into()));
    }

    let mut catalog_object: Option<(ObjectId, Object)> = None;
    let mut pages_object: Option<(ObjectId, Object)> = None;

    for (object_id, object) in documents_objects {
        match object.type_name().unwrap_or(b"") {
            b"Catalog" => {
                if catalog_object.is_none() {
                    catalog_object = Some((object_id, object));
                }
            }
            b"Pages" => {
                if let Ok(dict) = object.as_dict() {
                    let mut dict = dict.clone();
                    if let Some((_, ref existing)) = pages_object {
                        if let Ok(existing_dict) = existing.as_dict() {
                            dict.extend(existing_dict);
                        }
                    }
                    pages_object = Some((
                        pages_object.map(|(id, _)| id).unwrap_or(object_id),
                        Object::Dictionary(dict),
                    ));
                }
            }
            b"Page" | b"Outlines" | b"Outline" => {}
            _ => {
                merged.objects.insert(object_id, object);
            }
        }
    }

    let (pages_id, pages_obj) = pages_object
        .ok_or_else(|| ScanError::Pdf("Missing Pages dictionary in source PDFs".into()))?;
    let (catalog_id, catalog_obj) = catalog_object
        .ok_or_else(|| ScanError::Pdf("Missing Catalog dictionary in source PDFs".into()))?;

    let mut kids: Vec<Object> = Vec::with_capacity(documents_pages.len());
    for (page_id, mut page_obj) in documents_pages {
        if let Ok(dict) = page_obj.as_dict_mut() {
            dict.set("Parent", pages_id);
        }
        merged.objects.insert(page_id, page_obj);
        kids.push(Object::Reference(page_id));
    }

    let mut pages_dict = pages_obj
        .as_dict()
        .map_err(|e| ScanError::Pdf(e.to_string()))?
        .clone();
    pages_dict.set("Count", kids.len() as u32);
    pages_dict.set("Kids", Object::Array(kids));
    merged.objects.insert(pages_id, Object::Dictionary(pages_dict));

    let mut catalog_dict = catalog_obj
        .as_dict()
        .map_err(|e| ScanError::Pdf(e.to_string()))?
        .clone();
    catalog_dict.set("Pages", pages_id);
    catalog_dict.remove(b"Outlines");
    merged.objects.insert(catalog_id, Object::Dictionary(catalog_dict));

    merged.trailer.set("Root", catalog_id);
    merged.max_id = merged.objects.len() as u32;
    merged.renumber_objects();

    if let Some(parent) = Path::new(out_path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    merged.save(out_path)?;
    Ok(())
}

/// Split a PDF into one output file per requested 1-based inclusive `PageRange`.
pub fn split_pdf_file(
    input: &str,
    out_dir: &str,
    ranges: &[PageRange],
) -> Result<Vec<String>, ScanError> {
    if ranges.is_empty() {
        return Err(ScanError::InvalidArgument("No page ranges provided".into()));
    }

    let src_doc = Document::load(input)?;
    if src_doc.is_encrypted() {
        return Err(ScanError::EncryptedPdf);
    }

    let total_pages = src_doc.get_pages().len() as u32;
    if total_pages == 0 {
        return Err(ScanError::Pdf("Source PDF has 0 pages".into()));
    }

    fs::create_dir_all(out_dir)?;
    let stem = Path::new(input)
        .file_stem()
        .and_then(|s| s.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("document");

    let mut outputs = Vec::with_capacity(ranges.len());

    for (i, range) in ranges.iter().enumerate() {
        if range.start == 0 || range.end < range.start || range.end > total_pages {
            return Err(ScanError::InvalidArgument(format!(
                "Invalid range {}-{} (total pages: {})",
                range.start, range.end, total_pages
            )));
        }

        let mut part = src_doc.clone();
        let to_delete: Vec<u32> = (1..=total_pages)
            .filter(|p| *p < range.start || *p > range.end)
            .collect();
        if !to_delete.is_empty() {
            part.delete_pages(&to_delete);
        }
        part.prune_objects();
        part.renumber_objects();

        let file_name = if range.start == range.end {
            format!("{}_p{}.pdf", stem, range.start)
        } else {
            format!("{}_p{}-{}.pdf", stem, range.start, range.end)
        };
        let mut out_path = Path::new(out_dir).join(&file_name);
        if outputs.iter().any(|p| p == &out_path.to_string_lossy()) {
            out_path = Path::new(out_dir).join(format!("{}_part{}.pdf", stem, i + 1));
        }
        part.save(&out_path)?;
        outputs.push(out_path.to_string_lossy().into_owned());
    }

    Ok(outputs)
}

/// Load a file as raw JPEG bytes without re-encoding if it is already a standard JPEG;
/// otherwise decode (applying EXIF) and encode to JPEG.
fn load_as_jpeg_stream(path: &str, quality: u8) -> Result<(Vec<u8>, u32, u32, &'static str), ScanError> {
    let raw = fs::read(path)?;
    if let Some((w, h, comps)) = parse_jpeg_sof(&raw) {
        let cs = match comps {
            1 => "DeviceGray",
            3 => "DeviceRGB",
            4 => "DeviceCMYK",
            _ => "DeviceRGB",
        };
        return Ok((raw, w, h, cs));
    }

    let img = open_oriented_image(path)?.to_rgb8();
    let (w, h) = img.dimensions();
    let mut buf = Cursor::new(Vec::new());
    let mut enc = JpegEncoder::new_with_quality(&mut buf, quality.clamp(30, 100));
    enc.encode_image(&img)?;
    Ok((buf.into_inner(), w, h, "DeviceRGB"))
}

/// Inspect JPEG Start-Of-Frame marker to obtain (width, height, components) without decoding pixels.
fn parse_jpeg_sof(data: &[u8]) -> Option<(u32, u32, u8)> {
    if data.len() < 4 || data[0] != 0xFF || data[1] != 0xD8 {
        return None;
    }
    let mut i = 2usize;
    while i + 3 < data.len() {
        if data[i] != 0xFF {
            return None;
        }
        while i < data.len() && data[i] == 0xFF {
            i += 1;
        }
        if i >= data.len() {
            return None;
        }
        let marker = data[i];
        i += 1;
        if marker == 0xD9 || marker == 0xDA {
            return None;
        }
        if (0xD0..=0xD7).contains(&marker) || marker == 0x01 {
            continue;
        }
        if i + 1 >= data.len() {
            return None;
        }
        let seg_len = u16::from_be_bytes([data[i], data[i + 1]]) as usize;
        if seg_len < 2 || i + seg_len > data.len() {
            return None;
        }
        let is_sof = matches!(
            marker,
            0xC0 | 0xC1 | 0xC2 | 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB | 0xCD | 0xCE | 0xCF
        );
        if is_sof && seg_len >= 8 {
            let h = u16::from_be_bytes([data[i + 3], data[i + 4]]) as u32;
            let w = u16::from_be_bytes([data[i + 5], data[i + 6]]) as u32;
            let comps = data[i + 7];
            if w > 0 && h > 0 {
                return Some((w, h, comps));
            }
            return None;
        }
        i += seg_len;
    }
    None
}

fn sanitize_pdf_ascii(input: &str) -> String {
    input
        .trim()
        .chars()
        .filter(|c| c.is_ascii() && !c.is_control())
        .take(60)
        .flat_map(|c| match c {
            '(' | ')' | '\\' => vec!['\\', c],
            other => vec![other],
        })
        .collect()
}
