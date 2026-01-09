# author : Matthias Lapu (CEA)
FROM python:3.11-slim

WORKDIR /jureptool

COPY requirements.txt .

RUN pip install --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY src src/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fonts-liberation \
        fontconfig && \
        fc-cache -f -v && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "python3", "src/main.py" ]