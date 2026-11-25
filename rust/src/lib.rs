mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod api;
mod archive;
mod detect;
mod enhance;
pub mod error;
mod pdf;
mod warp;

#[cfg(test)]
mod tests {
    use std::fs::File;

    use image::{GrayImage, Luma, Rgb, RgbImage};
    use lopdf::Document;
    use zip::ZipArchive;

    use crate::api::{
        compose_id_card, detect_corners_from_file, detect_corners_live, export_image,
        images_to_pdf, make_thumbnail, merge_pdfs, process_page, split_pdf, zip_files,
        ExportImageFormat, FilterKind, PageRange, PdfFit, PdfOpts, Quad, ZipEntry,
    };
    use crate::enhance::sauvola_binarize;
    use crate::warp::warp_perspective;

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("jscan_test_{}_{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn make_synthetic_doc_image(w: u32, h: u32) -> RgbImage {
        let mut img = RgbImage::from_pixel(w, h, Rgb([25, 25, 25]));
        // White paper sheet in the middle (~56% of frame area).
        let x0 = (w as f32 * 0.12) as u32;
        let x1 = (w as f32 * 0.88) as u32;
        let y0 = (h as f32 * 0.12) as u32;
        let y1 = (h as f32 * 0.88) as u32;
        for y in y0..y1 {
            for x in x0..x1 {
                img.put_pixel(x, y, Rgb([240, 240, 240]));
            }
        }
        // Dark text bars inside the sheet.
        for line in 0..5 {
            let ly = y0 + 25 + line * 24;
            if ly + 6 < y1 {
                for y in ly..(ly + 6) {
                    for x in (x0 + 20)..(x1 - 20) {
                        img.put_pixel(x, y, Rgb([30, 30, 30]));
                    }
                }
            }
        }
        img
    }

    fn point_in_convex_quad(px: f64, py: f64, q: [(f64, f64); 4]) -> bool {
        let mut sign = 0.0f64;
        for i in 0..4 {
            let a = q[i];
            let b = q[(i + 1) % 4];
            let c = (b.0 - a.0) * (py - a.1) - (b.1 - a.1) * (px - a.0);
            if c.abs() < 1e-6 {
                continue;
            }
            if sign == 0.0 {
                sign = c;
            } else if sign * c < 0.0 {
                return false;
            }
        }
        true
    }

    #[test]
    fn detects_synthetic_rectangle_on_dark_background() {
        let dir = temp_dir("detect");
        let img = make_synthetic_doc_image(400, 300);
        let path = dir.join("doc.jpg");
        img.save(&path).unwrap();

        let quad = detect_corners_from_file(path.to_string_lossy().into_owned()).unwrap();
        assert!((quad.pts[0].0 - 0.12).abs() < 0.06, "TL x: {:?}", quad.pts);
        assert!((quad.pts[0].1 - 0.12).abs() < 0.06, "TL y: {:?}", quad.pts);
        assert!((quad.pts[2].0 - 0.88).abs() < 0.06, "BR x: {:?}", quad.pts);
        assert!((quad.pts[2].1 - 0.88).abs() < 0.06, "BR y: {:?}", quad.pts);

        let stride = 416u32;
        let mut y_buf = vec![0u8; (stride * 300) as usize];
        for y in 0..300 {
            for x in 0..400 {
                let p = img.get_pixel(x, y);
                y_buf[(y * stride + x) as usize] = p[0];
            }
        }
        let live = detect_corners_live(y_buf, 400, 300, stride, 0);
        assert!(live.is_some(), "Expected live quad detection to succeed");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn warp_returns_expected_dimensions() {
        let img = make_synthetic_doc_image(400, 300);
        let quad = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)];
        let warped = warp_perspective(&img, quad, 1000).unwrap();
        assert_eq!(warped.width(), 320);
        assert_eq!(warped.height(), 240);

        let capped = warp_perspective(&img, quad, 160).unwrap();
        assert_eq!(capped.width(), 160);
        assert_eq!(capped.height(), 120);
    }

    #[test]
    fn detects_tilted_trapezoid_and_low_contrast_colored_desk() {
        let dir = temp_dir("detect_trapezoid");
        let (w, h) = (480u32, 640u32);
        let mut img = RgbImage::from_pixel(w, h, Rgb([210, 180, 145]));
        let expected = [
            (0.22f64, 0.14f64),
            (0.78f64, 0.16f64),
            (0.88f64, 0.84f64),
            (0.12f64, 0.82f64),
        ];
        let q_px = [
            (expected[0].0 * (w - 1) as f64, expected[0].1 * (h - 1) as f64),
            (expected[1].0 * (w - 1) as f64, expected[1].1 * (h - 1) as f64),
            (expected[2].0 * (w - 1) as f64, expected[2].1 * (h - 1) as f64),
            (expected[3].0 * (w - 1) as f64, expected[3].1 * (h - 1) as f64),
        ];

        for y in 0..h {
            for x in 0..w {
                if point_in_convex_quad(x as f64, y as f64, q_px) {
                    img.put_pixel(x, y, Rgb([242, 242, 242]));
                }
            }
        }
        for row in 0..10 {
            let y0 = 160 + row * 32;
            for y in y0..(y0 + 5) {
                for x in 140..340 {
                    if point_in_convex_quad(x as f64, y as f64, q_px) {
                        img.put_pixel(x, y, Rgb([25, 25, 25]));
                    }
                }
            }
        }

        let path = dir.join("tilted_wood.jpg");
        img.save(&path).unwrap();
        let quad = detect_corners_from_file(path.to_string_lossy().into_owned()).unwrap();
        for i in 0..4 {
            let dx = (quad.pts[i].0 as f64 - expected[i].0).abs();
            let dy = (quad.pts[i].1 as f64 - expected[i].1).abs();
            assert!(
                dx < 0.025 && dy < 0.025,
                "Corner {} inaccurate: got {:?}, expected {:?} (all: {:?})",
                i,
                quad.pts[i],
                expected[i],
                quad.pts
            );
        }

        let mut y_buf = vec![0u8; (w * h) as usize];
        let (sw, sh) = (h, w);
        for ry in 0..h {
            for rx in 0..w {
                let p = img.get_pixel(rx, ry);
                let luma = ((77 * p[0] as u32 + 150 * p[1] as u32 + 29 * p[2] as u32) >> 8) as u8;
                let sx = ry;
                let sy = sh - 1 - rx;
                y_buf[(sy * sw + sx) as usize] = luma;
            }
        }
        let live = detect_corners_live(y_buf, sw, sh, sw, 90);
        assert!(live.is_some(), "Expected live detection on tilted low-contrast doc");
        let live_q = live.unwrap();
        for i in 0..4 {
            let dx = (live_q.pts[i].0 as f64 - expected[i].0).abs();
            let dy = (live_q.pts[i].1 as f64 - expected[i].1).abs();
            assert!(
                dx < 0.03 && dy < 0.03,
                "Live corner {} inaccurate: got {:?}, expected {:?}",
                i,
                live_q.pts[i],
                expected[i]
            );
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn warp_recovers_foreshortened_aspect_and_maps_corners_precisely() {
        let (w, h) = (600u32, 800u32);
        let u0 = (w - 1) as f64 * 0.5;
        let v0 = (h - 1) as f64 * 0.5;
        let f = 850.0f64;
        let pitch = 35.0f64.to_radians();
        let (sp, cp) = pitch.sin_cos();

        let doc_w = 210.0f64;
        let doc_h = 297.0f64;
        let z0 = 620.0f64;

        let project = |x3: f64, y3: f64| -> (f64, f64) {
            let yr = y3 * cp;
            let zr = z0 - y3 * sp;
            (u0 + f * x3 / zr, v0 + f * yr / zr)
        };

        let tl = project(-doc_w * 0.5, -doc_h * 0.5);
        let tr = project(doc_w * 0.5, -doc_h * 0.5);
        let br = project(doc_w * 0.5, doc_h * 0.5);
        let bl = project(-doc_w * 0.5, doc_h * 0.5);

        let mut img = RgbImage::from_pixel(w, h, Rgb([20, 20, 20]));
        let q_px = [tl, tr, br, bl];
        for y in 0..h {
            for x in 0..w {
                if point_in_convex_quad(x as f64, y as f64, q_px) {
                    img.put_pixel(x, y, Rgb([240, 240, 240]));
                }
            }
        }
        let paint_dot = |im: &mut RgbImage, c: (f64, f64), color: Rgb<u8>| {
            let cx = c.0.round() as i32;
            let cy = c.1.round() as i32;
            for dy in -6..=6 {
                for dx in -6..=6 {
                    let x = cx + dx;
                    let y = cy + dy;
                    if x >= 0 && y >= 0 && x < w as i32 && y < h as i32 {
                        im.put_pixel(x as u32, y as u32, color);
                    }
                }
            }
        };
        paint_dot(&mut img, tl, Rgb([255, 0, 0]));
        paint_dot(&mut img, tr, Rgb([0, 255, 0]));
        paint_dot(&mut img, br, Rgb([0, 0, 255]));
        paint_dot(&mut img, bl, Rgb([255, 255, 0]));

        let norm = [
            ((tl.0 / (w - 1) as f64) as f32, (tl.1 / (h - 1) as f64) as f32),
            ((tr.0 / (w - 1) as f64) as f32, (tr.1 / (h - 1) as f64) as f32),
            ((br.0 / (w - 1) as f64) as f32, (br.1 / (h - 1) as f64) as f32),
            ((bl.0 / (w - 1) as f64) as f32, (bl.1 / (h - 1) as f64) as f32),
        ];

        let warped = warp_perspective(&img, norm, 1200).unwrap();
        let got_ratio = warped.height() as f64 / warped.width() as f64;
        let true_ratio = doc_h / doc_w;
        assert!(
            (got_ratio - true_ratio).abs() < 0.08,
            "Expected A4 aspect ~{:.3}, got {:.3} ({}x{})",
            true_ratio,
            got_ratio,
            warped.width(),
            warped.height()
        );

        let p_tl = warped.get_pixel(1, 1);
        let p_tr = warped.get_pixel(warped.width() - 2, 1);
        let p_br = warped.get_pixel(warped.width() - 2, warped.height() - 2);
        let p_bl = warped.get_pixel(1, warped.height() - 2);
        assert!(p_tl[0] > 200 && p_tl[1] < 60, "TL color mismatch: {:?}", p_tl);
        assert!(p_tr[1] > 200 && p_tr[0] < 60, "TR color mismatch: {:?}", p_tr);
        assert!(p_br[2] > 200 && p_br[0] < 60, "BR color mismatch: {:?}", p_br);
        assert!(p_bl[0] > 200 && p_bl[1] > 200 && p_bl[2] < 60, "BL color mismatch: {:?}", p_bl);

        let scrambled = [norm[0], norm[2], norm[1], norm[3]];
        let warped2 = warp_perspective(&img, scrambled, 1200).unwrap();
        assert_eq!(warped2.dimensions(), warped.dimensions());
    }

    #[test]
    fn detects_doc_with_binder_clip_shadow_and_bright_cluttered_corner() {
        let dir = temp_dir("detect_obstructed");
        let (w, h) = (480u32, 640u32);
        let mut img = RgbImage::from_pixel(w, h, Rgb([40, 42, 46]));
        for y in 0..220 {
            for x in 0..170 {
                img.put_pixel(x, y, Rgb([215, 200, 180]));
            }
        }
        for x in 10..460 {
            let cy = (50.0 + 18.0 * (x as f32 * 0.04).sin()) as i32;
            for dy in -4..=4 {
                let y = cy + dy;
                if y >= 0 && y < h as i32 {
                    img.put_pixel(x, y as u32, Rgb([15, 15, 18]));
                }
            }
        }

        let expected = [
            (0.16f64, 0.21f64),
            (0.84f64, 0.18f64),
            (0.89f64, 0.85f64),
            (0.10f64, 0.82f64),
        ];
        let q_px = [
            (expected[0].0 * (w - 1) as f64, expected[0].1 * (h - 1) as f64),
            (expected[1].0 * (w - 1) as f64, expected[1].1 * (h - 1) as f64),
            (expected[2].0 * (w - 1) as f64, expected[2].1 * (h - 1) as f64),
            (expected[3].0 * (w - 1) as f64, expected[3].1 * (h - 1) as f64),
        ];

        // Realistic soft Gaussian phone shadow across left half of white paper.
        for y in 0..h {
            for x in 0..w {
                if point_in_convex_quad(x as f64, y as f64, q_px) {
                    let dx = (x as f64 - 180.0) / 110.0;
                    let dy = (y as f64 - 380.0) / 170.0;
                    let shadow = (55.0 * (-(dx * dx + dy * dy)).exp()).round() as u8;
                    let v = 238u8.saturating_sub(shadow);
                    img.put_pixel(x, y, Rgb([v, v, v]));
                }
            }
        }
        // Black binder clip covering the TL corner of the paper.
        let tl_x = q_px[0].0.round() as i32;
        let tl_y = q_px[0].1.round() as i32;
        for dy in -12..=22 {
            for dx in -12..=28 {
                let x = tl_x + dx;
                let y = tl_y + dy;
                if x >= 0 && y >= 0 && x < w as i32 && y < h as i32 {
                    img.put_pixel(x as u32, y as u32, Rgb([18, 20, 22]));
                }
            }
        }

        let path = dir.join("obstructed.jpg");
        img.save(&path).unwrap();
        let quad = detect_corners_from_file(path.to_string_lossy().into_owned()).unwrap();
        for i in 0..4 {
            let dx = (quad.pts[i].0 as f64 - expected[i].0).abs();
            let dy = (quad.pts[i].1 as f64 - expected[i].1).abs();
            assert!(
                dx < 0.03 && dy < 0.03,
                "Obstructed corner {} inaccurate: got {:?}, expected {:?} (all: {:?})",
                i,
                quad.pts[i],
                expected[i],
                quad.pts
            );
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sauvola_produces_strictly_binary_output() {
        let mut gray = GrayImage::from_pixel(160, 120, Luma([225]));
        for y in 40..60 {
            for x in 30..130 {
                gray.put_pixel(x, y, Luma([35]));
            }
        }
        let bw = sauvola_binarize(&gray, 0.2);
        let mut has_black = false;
        let mut has_white = false;
        for &v in bw.as_raw() {
            assert!(v == 0 || v == 255, "Non-binary pixel value: {}", v);
            if v == 0 {
                has_black = true;
            } else {
                has_white = true;
            }
        }
        assert!(has_black && has_white, "Expected both foreground and background pixels");
    }

    #[test]
    fn pdf_create_merge_split_and_zip_work() {
        let dir = temp_dir("pdf_zip");
        let img = make_synthetic_doc_image(300, 400);
        let src = dir.join("orig.jpg");
        img.save(&src).unwrap();

        let mut page_paths = Vec::new();
        for i in 1..=3 {
            let dst = dir.join(format!("p{}.jpg", i));
            let out = process_page(
                src.to_string_lossy().into_owned(),
                dst.to_string_lossy().into_owned(),
                Quad {
                    pts: vec![(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)],
                },
                FilterKind::Color,
                0,
                600,
                85,
                0.15,
                0.1,
            )
            .unwrap();
            assert!(out.width > 0 && out.height > 0);
            page_paths.push(dst.to_string_lossy().into_owned());
        }

        let id_out = dir.join("id_card.jpg");
        let id_dims = compose_id_card(
            page_paths[0].clone(),
            page_paths[1].clone(),
            id_out.to_string_lossy().into_owned(),
            1200,
            85,
        )
        .unwrap();
        assert_eq!(id_dims.height, 1200);
        assert!(id_dims.width < id_dims.height);

        let wm_png = dir.join("wm.png");
        export_image(
            page_paths[0].clone(),
            wm_png.to_string_lossy().into_owned(),
            ExportImageFormat::Png,
            600,
            85,
            Some("VERIFIKASI".into()),
        )
        .unwrap();
        assert!(wm_png.exists());

        let thumb = dir.join("thumb.jpg");
        make_thumbnail(page_paths[0].clone(), thumb.to_string_lossy().into_owned(), 120).unwrap();
        assert!(thumb.exists());

        let pdf1 = dir.join("doc1.pdf");
        images_to_pdf(
            page_paths.clone(),
            pdf1.to_string_lossy().into_owned(),
            PdfOpts {
                fit: PdfFit::A4,
                jpeg_quality: 85,
                margin_pt: 24.0,
                watermark_text: Some("HANYA UNTUK VERIFIKASI".into()),
            },
        )
        .unwrap();
        let reopened = Document::load(&pdf1).unwrap();
        assert_eq!(reopened.get_pages().len(), 3);

        let pdf2 = dir.join("doc2.pdf");
        std::fs::copy(&pdf1, &pdf2).unwrap();
        let merged = dir.join("merged.pdf");
        merge_pdfs(
            vec![
                pdf1.to_string_lossy().into_owned(),
                pdf2.to_string_lossy().into_owned(),
            ],
            merged.to_string_lossy().into_owned(),
        )
        .unwrap();
        assert_eq!(Document::load(&merged).unwrap().get_pages().len(), 6);

        let split_dir = dir.join("split");
        let split_files = split_pdf(
            merged.to_string_lossy().into_owned(),
            split_dir.to_string_lossy().into_owned(),
            vec![PageRange { start: 1, end: 2 }, PageRange { start: 4, end: 6 }],
        )
        .unwrap();
        assert_eq!(split_files.len(), 2);
        assert_eq!(Document::load(&split_files[0]).unwrap().get_pages().len(), 2);
        assert_eq!(Document::load(&split_files[1]).unwrap().get_pages().len(), 3);

        let zip_path = dir.join("bundle.zip");
        zip_files(
            vec![
                ZipEntry {
                    src_path: page_paths[0].clone(),
                    name_in_zip: "dokumen_1.jpg".into(),
                },
                ZipEntry {
                    src_path: page_paths[1].clone(),
                    name_in_zip: "dokumen_2.jpg".into(),
                },
            ],
            zip_path.to_string_lossy().into_owned(),
        )
        .unwrap();
        let mut archive = ZipArchive::new(File::open(&zip_path).unwrap()).unwrap();
        assert_eq!(archive.len(), 2);
        assert_eq!(archive.by_index(0).unwrap().name().unwrap().as_ref(), "dokumen_1.jpg");
        assert_eq!(archive.by_index(1).unwrap().name().unwrap().as_ref(), "dokumen_2.jpg");

        let _ = std::fs::remove_dir_all(&dir);
    }
}
