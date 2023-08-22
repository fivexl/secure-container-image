# Sample of creation python-poetry image
## Build image and run container
```bash
docker build -t python-poetry .
docker run -d -p 8000:80 python-poetry
```
## Test
```bash
curl http://localhost:8000
curl http://localhost:8000/stats 
```

