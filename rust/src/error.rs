use thiserror::Error;

#[derive(Debug, Error)]
pub enum ScanError {
    #[error("I/O error: {0}")]
    Io(String),
    #[error("Image error: {0}")]
    Image(String),
    #[error("Invalid quad coordinates")]
    InvalidQuad,
    #[error("PDF error: {0}")]
    Pdf(String),
    #[error("PDF is encrypted and cannot be processed")]
    EncryptedPdf,
    #[error("Archive error: {0}")]
    Zip(String),
    #[error("Invalid argument: {0}")]
    InvalidArgument(String),
}

impl From<std::io::Error> for ScanError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}

impl From<image::ImageError> for ScanError {
    fn from(e: image::ImageError) -> Self {
        Self::Image(e.to_string())
    }
}

impl From<lopdf::Error> for ScanError {
    fn from(e: lopdf::Error) -> Self {
        let msg = e.to_string();
        let lower = msg.to_ascii_lowercase();
        if lower.contains("encrypt") || lower.contains("decrypt") || lower.contains("password") {
            Self::EncryptedPdf
        } else {
            Self::Pdf(msg)
        }
    }
}

impl From<zip::result::ZipError> for ScanError {
    fn from(e: zip::result::ZipError) -> Self {
        Self::Zip(e.to_string())
    }
}
