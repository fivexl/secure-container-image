# Sample of creation python-poetry image without venv
## Build image and run container
```bash
docker build -t python-poetry-without-venv .
docker run -d -p 8000:80 python-poetry-without-venv
```
## Test
```bash
curl http://localhost:8000
curl http://localhost:8000/stats 
```



