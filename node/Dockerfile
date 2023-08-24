# Use the official Node.js image from Docker Hub for building
FROM node:16 AS build

WORKDIR /deps

# Copy package.json and package-lock.json for installing dependencies
COPY package*.json ./

# Install the Node.js dependencies
RUN npm install


# Use Google's Distroless Node.js image
FROM gcr.io/distroless/nodejs:16 AS runtime

WORKDIR /app

# Copy over the deps
COPY --from=build /deps /app
# Copy the rest of the project over
COPY ./app /app

CMD ["server.js"]
# docker run -d -p 8000:80 test
# docker build -t test .       