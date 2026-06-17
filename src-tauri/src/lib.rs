use base64::{engine::general_purpose::STANDARD, Engine};
use std::fs;
use std::path::PathBuf;
use tauri::Manager;

/// App data root (created on demand): %APPDATA%/<bundle id> on Windows.
fn data_root(app: &tauri::AppHandle) -> PathBuf {
    let p = app
        .path()
        .app_data_dir()
        .unwrap_or_else(|_| PathBuf::from("."));
    let _ = fs::create_dir_all(&p);
    p
}

fn sanitize(name: &str) -> String {
    name.chars()
        .map(|c| if c.is_alphanumeric() || c == '.' || c == '-' || c == '_' { c } else { '_' })
        .collect()
}

fn apply_wallpaper(path: &str) -> Result<(), String> {
    wallpaper::set_from_path(path).map_err(|e| e.to_string())?;
    // Fill the screen (crop overflow) to match the macOS behavior.
    let _ = wallpaper::set_mode(wallpaper::Mode::Crop);
    Ok(())
}

#[tauri::command]
fn app_data_dir(app: tauri::AppHandle) -> String {
    data_root(&app).to_string_lossy().to_string()
}

/// Set an already-local file as the desktop wallpaper.
#[tauri::command]
fn set_wallpaper_path(path: String) -> Result<(), String> {
    apply_wallpaper(&path)
}

/// Download a remote image into the app's downloads folder, then set it as wallpaper.
#[tauri::command]
async fn set_wallpaper_url(app: tauri::AppHandle, url: String) -> Result<String, String> {
    let path = download_file(app, "downloads".into(), None, url).await?;
    apply_wallpaper(&path)?;
    Ok(path)
}

/// Save a base64 (no data: prefix) image under <data>/<subdir>/<name>; returns the absolute path.
#[tauri::command]
fn save_b64(app: tauri::AppHandle, subdir: String, name: String, b64: String) -> Result<String, String> {
    let payload = b64.split(',').last().unwrap_or(&b64);
    let bytes = STANDARD.decode(payload).map_err(|e| e.to_string())?;
    let dir = data_root(&app).join(sanitize(&subdir));
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(sanitize(&name));
    fs::write(&path, &bytes).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

/// Download a remote file into <data>/<subdir>; returns the absolute path.
#[tauri::command]
async fn download_file(
    app: tauri::AppHandle,
    subdir: String,
    name: Option<String>,
    url: String,
) -> Result<String, String> {
    let resp = reqwest::get(&url).await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status()));
    }
    let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    let fname = name.unwrap_or_else(|| {
        let last = url.split('/').last().unwrap_or("image").to_string();
        let last = last.split('?').next().unwrap_or("image").to_string();
        if last.contains('.') { last } else { format!("{}.jpg", last) }
    });
    let dir = data_root(&app).join(sanitize(&subdir));
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(sanitize(&fname));
    fs::write(&path, &bytes).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

/// GET a URL and return the response body as text (used to proxy the Wallhaven API past CORS).
#[tauri::command]
async fn http_get(url: String) -> Result<String, String> {
    let resp = reqwest::get(&url).await.map_err(|e| e.to_string())?;
    resp.text().await.map_err(|e| e.to_string())
}

/// List image files in a folder (non-recursive), sorted by name.
#[tauri::command]
fn list_images(dir: String) -> Vec<String> {
    let exts = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "heic", "heif"];
    let mut out: Vec<String> = match fs::read_dir(&dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| {
                p.extension()
                    .and_then(|x| x.to_str())
                    .map(|x| exts.contains(&x.to_lowercase().as_str()))
                    .unwrap_or(false)
            })
            .map(|p| p.to_string_lossy().to_string())
            .collect(),
        Err(_) => Vec::new(),
    };
    out.sort();
    out
}

/// Read a small JSON store file from the data dir; "" when missing.
#[tauri::command]
fn read_store(app: tauri::AppHandle, name: String) -> String {
    fs::read_to_string(data_root(&app).join(sanitize(&name))).unwrap_or_default()
}

#[tauri::command]
fn write_store(app: tauri::AppHandle, name: String, contents: String) -> Result<(), String> {
    fs::write(data_root(&app).join(sanitize(&name)), contents).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_data_dir,
            set_wallpaper_path,
            set_wallpaper_url,
            save_b64,
            download_file,
            http_get,
            list_images,
            read_store,
            write_store
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
