# colmap-openmvs

A robust, production-ready photogrammetry pipeline combining [COLMAP](https://github.com/colmap/colmap) and [OpenMVS](https://github.com/cdcseacave/openMVS), containerized for reproducibility and ease of use. Supports both CPU-only and CUDA-accelerated environments: run the full pipeline on any machine, or leverage GPU acceleration for faster processing when available.

## Features

- **End-to-End Photogrammetry**: From unordered images to textured 3D meshes, fully automated.
- **CPU & CUDA Support**: Choose CPU for maximum compatibility (even on GPU-less servers), or CUDA for optimal speed (with a larger image size). Both are first-class citizens.
- **Latest Development Versions**: Always up-to-date with automated, tested builds.
- **Dockerized**: Run anywhere with a single command; no dependency hell.
- **Intelligent Caching**: Only re-runs steps when inputs change.
- **Verbose Logging & Dry-Run**: Debug and inspect every step, or simulate runs without execution.
- **User Mapping**: Use `-u $(id -u):$(id -g)` for proper file permissions on output.
- **Comprehensive Help**: `--help` provides detailed info about all embedded tools and configuration options.

## Quickstart

1. **Prepare your images** 

Place your images in a directory with a subfolder called `images/`:
```
/your/data/path/
  images/
    img1.jpg
    img2.jpg
    ...
```

2. **(Optional) Add a custom config**  

You can create a `config.sh` file in your data directory to override environment variables and fine-tune the pipeline.

To see all available options and configuration variables:
```sh
docker run --rm -it yeicor/colmap-openmvs:cpu-latest --help
```

3. **Run the pipeline using Docker**  

For CPU-only (compatible with all systems):
```sh
docker run --rm -it -u $(id -u):$(id -g) \
  -v /your/data/path:/data \
  yeicor/colmap-openmvs:cpu-latest /data
```

For CUDA acceleration (requires NVIDIA GPU and drivers):
```sh
docker run --rm -it --gpus all -u $(id -u):$(id -g) \
  -v /your/data/path:/data \
  yeicor/colmap-openmvs:cuda-latest /data
```

Happy reconstructing!
