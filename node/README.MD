# Sample of creation distroless node image
## Build image and run container
```bash
docker build -t node_image_example .
docker run -d -p 8000:80 node_image_example
```
## Test
```bash
curl http://localhost:8000
curl http://localhost:8000/stats 
```

