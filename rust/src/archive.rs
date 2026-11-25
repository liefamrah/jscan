use std::collections::HashSet;
use std::fs::{self, File};
use std::io;
use std::path::Path;

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

use crate::api::ZipEntry;
use crate::error::ScanError;

/// Package a list of files into a ZIP archive.
/// Already-compressed formats (JPG/PNG) use Stored mode to avoid wasted CPU.
pub fn create_zip_archive(entries: &[ZipEntry], out_zip: &str) -> Result<(), ScanError> {
    if entries.is_empty() {
        return Err(ScanError::InvalidArgument("No entries provided for ZIP".into()));
    }
    if let Some(parent) = Path::new(out_zip).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }

    let file = File::create(out_zip)?;
    let mut zip = ZipWriter::new(file);
    let mut used_names = HashSet::new();

    for entry in entries {
        let safe_name = unique_entry_name(&sanitize_zip_name(&entry.name_in_zip), &mut used_names);
        let lower = safe_name.to_ascii_lowercase();
        let method = if lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".png") {
            CompressionMethod::Stored
        } else {
            CompressionMethod::Deflated
        };
        let options = SimpleFileOptions::default().compression_method(method);
        zip.start_file(&safe_name, options)?;
        let mut src = File::open(&entry.src_path)?;
        io::copy(&mut src, &mut zip)?;
    }

    zip.finish()?;
    Ok(())
}

fn sanitize_zip_name(name: &str) -> String {
    let cleaned: String = name
        .replace('\\', "/")
        .split('/')
        .filter(|seg| !seg.is_empty() && *seg != "." && *seg != "..")
        .collect::<Vec<_>>()
        .join("_");
    let cleaned: String = cleaned
        .chars()
        .map(|c| match c {
            '<' | '>' | ':' | '"' | '|' | '?' | '*' => '_',
            c if c.is_control() => '_',
            _ => c,
        })
        .collect();
    if cleaned.is_empty() {
        "file".to_string()
    } else {
        cleaned
    }
}

fn unique_entry_name(name: &str, used: &mut HashSet<String>) -> String {
    if used.insert(name.to_string()) {
        return name.to_string();
    }
    let path = Path::new(name);
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or(name);
    let ext = path.extension().and_then(|s| s.to_str());
    let mut idx = 2u32;
    loop {
        let candidate = match ext {
            Some(e) if !e.is_empty() => format!("{}_{}.{}", stem, idx, e),
            _ => format!("{}_{}", stem, idx),
        };
        if used.insert(candidate.clone()) {
            return candidate;
        }
        idx += 1;
    }
}
