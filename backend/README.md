cat > backend/README.md <<'EOF'
This directory contains private backend code (FastAPI + scrapers).
All real source files are intentionally .gitignored to keep secrets/private logic out of the public repo.

Public artifacts kept here:
- .env.example : safe placeholder env variables (no secrets)
- OPENAPI.md   : optional API docs (add later if you want)
  EOF