FROM python:3.11-slim

# CmdStan (Prophet backend) requires a C++ compiler and make to compile Stan models.
# Install them before pip so the cmdstanpy install step can find them.
RUN apt-get update && apt-get install -y --no-install-recommends \
        g++ \
        make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .

# Install all Python deps (includes cmdstanpy==1.2.4 and prophet==1.1.5)
RUN pip install --no-cache-dir -r requirements.txt

# Pre-install CmdStan into the image so the first forecast request doesn't
# trigger a runtime download/compile (which would time out or fail in airgapped envs).
RUN python -c "import cmdstanpy; cmdstanpy.install_cmdstan()"

COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
