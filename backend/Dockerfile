FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies from pyproject.toml without installing the project itself
COPY pyproject.toml ./
RUN pip install --no-cache-dir $(python -c "import tomllib; deps=tomllib.load(open('pyproject.toml','rb'))['project']['dependencies']; print(' '.join(deps))")

COPY . .

# Ensure the app package is importable (needed for alembic env.py)
ENV PYTHONPATH=/app

EXPOSE 8000
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
