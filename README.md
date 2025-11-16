# NFL Props App

This repo contains a backend API and a simple frontend to view NFL projections and props. The architecture has:

- FastAPI backend (backend/api.py)
- Background recompute worker (scripts/generate_projections.py invoked by app/services/worker.py)
- Scheduler using APScheduler (app/services/scheduler.py)
- Minimal React + Vite frontend (frontend/)
- Docker + docker-compose for local development

Run locally (quick):

1. Install dependencies: pip install -r requirements.txt
2. Start API: uvicorn backend.api:app --reload
3. Start frontend dev server: cd frontend && npm install && npm run dev

Or run with docker-compose:

  docker-compose up --build
