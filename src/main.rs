use std::{fs, io, process::exit, sync::OnceLock};

use actix_web::{App, HttpServer, get, middleware, post, web};
use anyhow::{Result, anyhow, bail};
use camino::Utf8PathBuf;
use colored::Colorize;
use dialoguer::Confirm;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

#[derive(Debug, Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// The name of the project
    pub project_name: String,
    /// Port to run the server on
    pub port: u16,
    /// Directory to place `sourcemap.json`
    pub sourcemap_directory: Utf8PathBuf,
    /// Directory to scrape for file paths
    pub file_paths_scrape_directory: Utf8PathBuf,
    /// Minimum log level to output
    pub log_level: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            project_name: Utf8PathBuf::from(".")
                .canonicalize_utf8()
                .unwrap()
                .file_name()
                .unwrap()
                .to_owned(),
            port: 33752,
            sourcemap_directory: ".".into(),
            file_paths_scrape_directory: ".".into(),
            log_level: "info".into(),
        }
    }
}

static CACHED_CONFIG: OnceLock<Config> = OnceLock::new();
impl Config {
    pub const PATH: &str = "axosync.toml";

    pub fn get() -> Result<Config> {
        if let Some(config) = CACHED_CONFIG.get().cloned() {
            return Ok(config);
        }

        match fs::read_to_string(Self::PATH) {
            Ok(content) => {
                #[derive(Deserialize)]
                #[serde(deny_unknown_fields)]
                struct ConfigToml {
                    config: Config,
                }
                let ConfigToml { config } = toml::from_str(&content)?;
                if !config.sourcemap_directory.is_dir() {
                    println!(
                        "{} {} is not a valid directory.",
                        "Warning (config.sourcemap_directory):"
                            .bright_yellow()
                            .bold(),
                        config.sourcemap_directory
                    );
                }
                if !config.file_paths_scrape_directory.is_dir() {
                    println!(
                        "{} {} is not a valid directory.",
                        "Warning (config.file_paths_scrape_directory):"
                            .bright_yellow()
                            .bold(),
                        config.file_paths_scrape_directory
                    );
                }
                CACHED_CONFIG.set(config.clone()).ok();
                Ok(config)
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                let Config {
                    project_name,
                    port,
                    sourcemap_directory,
                    file_paths_scrape_directory,
                    log_level,
                } = Config::default();
                let mut out = String::from(
                    "#:schema https://raw.githubusercontent.com/angeld23/axosync/refs/heads/main/schema.json",
                );
                out.push_str("\n\n[config]");
                {
                    out.push_str(&format!("\nproject_name = {project_name:?}"));
                    out.push_str(&format!("\nport = {port}"));
                    out.push_str(&format!("\nsourcemap_directory = {sourcemap_directory:?}"));
                    out.push_str(&format!(
                        "\nfile_paths_scrape_directory = {file_paths_scrape_directory:?}"
                    ));
                    out.push_str(&format!("\nlog_level = {log_level:?}"));
                }
                fs::write(Self::PATH, out)?;

                println!(
                    "Created {} in the current directory.",
                    Self::PATH.bright_blue().bold()
                );
                println!("You can edit it before continuing if you wish.");
                if !Confirm::new()
                    .with_prompt("Continue?".bold().to_string())
                    .default(true)
                    .show_default(true)
                    .interact()?
                {
                    exit(0);
                }

                Self::get()
            }
            Err(other) => bail!(other),
        }
    }
}

#[get("/getFilePaths")]
async fn get_file_paths() -> actix_web::Result<String> {
    let config = Config::get().unwrap();

    let mut paths = Vec::<Utf8PathBuf>::new();

    for entry in WalkDir::new(config.file_paths_scrape_directory).sort_by_file_name() {
        let path: Utf8PathBuf = entry.unwrap().into_path().try_into().unwrap();
        paths.push(
            path.canonicalize_utf8().unwrap().as_str()[4..]
                .replace("\\", "/")
                .into(),
        );
    }

    Ok(serde_json::to_string(&paths)?)
}

#[derive(Debug, Default, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SourcemapInstance {
    pub name: String,
    pub class_name: String,
    #[serde(skip_serializing_if = "core::ops::Not::not", default)]
    pub plugin_managed: bool,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub file_paths: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub children: Vec<SourcemapInstance>,
}

impl SourcemapInstance {
    pub fn path() -> Utf8PathBuf {
        let config = Config::get().unwrap();
        config.sourcemap_directory.join("sourcemap.json")
    }

    pub fn load() -> Result<SourcemapInstance> {
        let path = Self::path();
        if !path.exists() {
            Ok(SourcemapInstance::default())
        } else {
            let data = fs::read_to_string(path)?;
            Ok(serde_json::from_str(&data)?)
        }
    }

    pub fn save(&self) -> Result<()> {
        let path = Self::path();
        let data = serde_json::to_string_pretty(self)?;
        fs::write(path, data)?;
        Ok(())
    }

    pub fn find_first_child(&self, name: &str) -> Option<&SourcemapInstance> {
        self.children.iter().find(|child| child.name == name)
    }

    pub fn find_first_child_mut(&mut self, name: &str) -> Option<&mut SourcemapInstance> {
        self.children.iter_mut().find(|child| child.name == name)
    }
}

#[derive(Debug, Default, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SourcemapSetRequest {
    pub path: Vec<String>,
    pub value: Option<SourcemapInstance>,
    pub no_overwrite_children: bool,
}

#[post("/sourcemapSet")]
async fn sourcemap_set(requests: web::Json<Vec<SourcemapSetRequest>>) -> actix_web::Result<()> {
    let requests = requests.into_inner();

    let mut top = SourcemapInstance::load().unwrap();
    for req in requests {
        if req.path.is_empty() {
            top = req.value.ok_or_else(|| {
                actix_web::error::ErrorBadRequest(anyhow!(
                    "Path cannot be empty when setting top-level value"
                ))
            })?;

            continue;
        }

        let mut current = &mut top;
        for name in req.path.iter().take(req.path.len().saturating_sub(1)) {
            let current_class_name = current.class_name.clone();
            let current_name = current.name.clone();
            current = current.find_first_child_mut(name).ok_or_else(|| {
                actix_web::error::ErrorBadRequest(anyhow!(
                    "\"{}\" is not a valid member of {} {}",
                    name,
                    current_class_name,
                    current_name
                ))
            })?;
        }

        if let Some(mut value) = req.value {
            if let Some(name) = req.path.last()
                && let Some(child) = current.find_first_child_mut(name)
            {
                if req.no_overwrite_children {
                    value.children = child.children.clone();
                }
                *child = value;
            } else {
                current.children.push(value);
            }
        } else if let Some(name) = req.path.last() {
            current.children.retain(|child| &child.name != name);
        }
    }
    top.save().unwrap();

    Ok(())
}

#[get("/getProjectFolderName")]
async fn get_project_folder_name() -> String {
    Config::get().unwrap().project_name
}

#[actix_web::main]
async fn main() -> Result<()> {
    let config = Config::get()?;
    env_logger::init_from_env(env_logger::Env::new().default_filter_or(&config.log_level));

    HttpServer::new(|| {
        App::new()
            .service(get_file_paths)
            .service(sourcemap_set)
            .service(get_project_folder_name)
            .wrap(middleware::Logger::default())
    })
    .bind(("127.0.0.1", config.port))?
    .workers(1) // single-threaded, to ensure requests are handled in the order they are received
    .run()
    .await?;

    Ok(())
}
