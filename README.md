# Normal OJ

## Clone this project

```bash
git clone --recurse-submodules https://github.com/2025-NTNU-Software-Engineering-Team-1/Normal-OJ-2025Team1.git

cd Normal-OJ-2025Team1

git submodule foreach --recursive git checkout main
```
## Overview of the project

NOJ consists of three parts:
1. **[Backend](https://github.com/Normal-OJ/Back-End)**: Python web server, provides RESTful API, communicates with the database and the sandbox.
2. **[Frontend](https://github.com/Normal-OJ/new-front-end)**: The user interface that interacts with the backend, written in Vue.js.
3. **[Sandbox](https://github.com/Normal-OJ/Sandbox)**: Takes the user's submission, compiles and executes the code, and returns the result to the backend.

Each subfolder in this project corresponds to a specific part of NOJ (Backend, Frontend, Sandbox) and includes its own package manager, such as `pnpm` or `poetry`. Ideally, each part could be developed separately and locally, please refer to the `README.md` file in each subfolder.

You may also be interested in this [Introduction](https://github.com/Normal-OJ).

## Build and Run the entire project

### Setup Backend

```bash
# Run 
mkdir -p ./Back-End/minio/data
```
### Setup Sandbox

1. Make sure you have Docker installed and running.
2. cd to `Sandbox` folder, run `./build.sh`, this will build the images you need to compile and execute user's submission.
3. Replace `working_dir` in `Sandbox/.config/submission.json` as stated in the logs of the previous step.
  - Recommend to use `/path/to/Normal-OJ/Sandbox/submissions`.
  - This directory is for storing the user's submission.

### Run Docker

#### Build images and start

```bash
# start
docker compose up -d
```

or if you want to rebuild the images

```bash
# rebuild
docker compose up --build -d
```

When you run `docker compose up`, Docker Compose automatically combines `docker compose.yml` and `docker compose.override.yml`. You can check the `docker compose.override.yml` file, and you'll see the frontend is running locally on port 8080.

In production, the frontend is hosted on Cloudflare Pages, not locally.

### Setup MinIO

You can skip this if you will not develop features related to Problems and Submissions.

Refer to the `docker-compose.override.yml` file for the following configurations:

1. Open the MinIO console at http://localhost:9001 and log in using the username (`MINIO_ROOT_USER`) and password (`MINIO_ROOT_PASSWORD`) specified in the yml file.
2. In the MinIO console, navigate to **Object Browser** and create a bucket with the name specified (`MINIO_BUCKET`).
3. In the MinIO console, navigate to **Access Keys** and create an access key (`MINIO_ACCESS_KEY`) and secret key (`MINIO_SECRET_KEY`).

#### Other commands

- `docker compose start`
- `docker compose restart [service]`
- `docker compose stop`
- `docker compose down`

### Visit the local NOJ page

Now you could visit http://localhost:8080 to see the NOJ page.

Login with the admin with
- username: `first_admin`
- password: `firstpasswordforadmin`

## Production Deployment

There are two deployment options depending on your infrastructure:

| Option | Use Case | Frontend | Backend | Reverse Proxy |
|--------|----------|----------|---------|---------------|
| **VM Deployment** | Self-hosted server, school VM | Docker + Caddy | Docker | Caddy on VM |
| **Cloud Deployment** | GCP, AWS, Azure | Cloudflare Pages | Cloud Run | Cloud Platform |

---

### Option A: Single VM Deployment

Best for self-hosted servers or school VMs where all services run on one machine.

#### Architecture

```
                    ┌─────────────────────────────────────┐
                    │            Single VM                │
                    ├─────────────────────────────────────┤
   Internet ──────▶ │  Caddy (Reverse Proxy + HTTPS)     │
                    │    ├── /api/* ──▶ Backend (Flask)  │
                    │    └── /*     ──▶ Frontend (Caddy) │
                    │                                     │
                    │  MongoDB, Redis, MinIO, Sandbox     │
                    └─────────────────────────────────────┘
```

#### Prerequisites

1. Docker and Docker Compose installed
2. Domain name pointing to your server IP
3. Ports 80 and 443 open for Let's Encrypt SSL verification

#### Environment Files Setup

```bash
cp -r .secret.example .secret
```

Edit the files in `.secret/`:
- `caddy.env` - Set `SITE_ADDRESS` to your domain (e.g., `noj.example.com`)
- `web.env` - Backend configuration
- `minio.env` - MinIO credentials
- `mongo-express.env` - MongoDB Express login (optional)
- `sandbox.env` - Sandbox configuration

#### Deploy

```bash
# Using deploy script (recommended)
./deploy.sh

# Or manually
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

#### Common Commands

```bash
# View logs
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f

# Restart specific service
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart [service]

# Stop all services
docker compose -f docker-compose.yml -f docker-compose.prod.yml down

# Update and redeploy
git submodule foreach 'git fetch --all && git pull'
./deploy.sh
```

#### SSL Certificate

Caddy automatically obtains SSL certificates from Let's Encrypt. If your firewall blocks ports 80/443, you can use self-signed certificates temporarily:

1. Edit `.config/Caddyfile.prod`
2. Uncomment `tls internal`
3. Restart Caddy

---

### Option B: Cloud Deployment (GCP)

Best for scalable production environments using Google Cloud Platform.

#### Architecture

```
   ┌──────────────────────────────────────────────────────────┐
   │                     GCP Architecture                     │
   ├──────────────────────────────────────────────────────────┤
   │                                                          │
   │   Cloudflare Pages (Frontend)                            │
   │   └── Static files, CDN, automatic HTTPS                 │
   │   └── URL: *.nfe.pages.dev                               │
   │                        │                                 │
   │                        ▼                                 │
   │   Cloud Run (Backend API)                                │
   │   └── Image: asia-east1-docker.pkg.dev/noj-team1/...     │
   │   └── Auto-scaling, managed HTTPS                        │
   │                        │                                 │
   │                        ▼                                 │
   │   Cloud Run / GCE (Sandbox)                              │
   │   MongoDB Atlas, Memorystore (Redis)                     │
   │                                                          │
   └──────────────────────────────────────────────────────────┘
```

#### Key Differences from VM Deployment

| Component | VM Deployment | Cloud Deployment |
|-----------|---------------|------------------|
| Frontend | Docker + Caddy | Cloudflare Pages (auto-deploy on push) |
| Backend | Docker container | Cloud Run (pull from Artifact Registry) |
| SSL/HTTPS | Caddy / Let's Encrypt | Cloud platform (automatic) |
| Reverse Proxy | Caddy | Not needed (Cloud Run handles routing) |
| CORS | Can be in Caddy or Flask | **Must be in Flask** (no Caddy) |
| Scaling | Manual | Automatic |

#### Prerequisites

1. GCP project with billing enabled
2. Artifact Registry configured (`asia-east1-docker.pkg.dev/noj-team1/...`)
3. Cloud Run services set up
4. Cloudflare Pages connected to frontend repository

#### Deploy Backend to Cloud Run

```bash
# Build and push image
docker build -t asia-east1-docker.pkg.dev/noj-team1/backend/noj-web:latest -f Back-End/Dockerfile.prod Back-End/
docker push asia-east1-docker.pkg.dev/noj-team1/backend/noj-web:latest

# Deploy to Cloud Run
gcloud run deploy noj-web \
  --image asia-east1-docker.pkg.dev/noj-team1/backend/noj-web:latest \
  --region asia-east1 \
  --allow-unauthenticated
```

#### Deploy Frontend to Cloudflare Pages

Frontend is automatically deployed when pushing to the `new-front-end` repository. Configure in Cloudflare Dashboard:

- **Build command**: `pnpm run build`
- **Build output directory**: `dist`
- **Environment variable**: `VITE_APP_API_BASE_URL=https://your-cloud-run-url.run.app/api`

#### CORS Configuration

Since Cloud deployment doesn't use Caddy, CORS must be handled in Flask backend. Set the environment variable:

```bash
CORS_ALLOWED_ORIGINS=https://your-domain.nfe.pages.dev,https://noj.tw
```

---

### Comparison Summary

| Aspect | VM Deployment | Cloud Deployment |
|--------|---------------|------------------|
| **Setup Complexity** | Lower | Higher |
| **Cost** | Fixed (VM cost) | Pay-per-use |
| **Scaling** | Manual | Automatic |
| **Maintenance** | Self-managed | Platform-managed |
| **SSL** | Caddy handles | Platform handles |
| **Best For** | Development, small scale | Production, high availability |

