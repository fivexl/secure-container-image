# Build using the appropriate Debian release
# * Install necessary dependencies to compile C Python modules
# * Use poetry for dependency management

# poetry config virtualenvs.options.no-pip true && \
# poetry config virtualenvs.options.no-setuptools true && \

FROM debian:11-slim AS build
ARG POETRY_VERSION=1.6.1

# Update and install dependencies
RUN apt-get update && \
  apt-get install --no-install-suggests --no-install-recommends --yes python3 python3-pip gcc libpython3-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  pip install "poetry==${POETRY_VERSION}"

# Copy just the pyproject.toml and poetry.lock files to install dependencies
COPY pyproject.toml poetry.lock ./

# Disable the creation of virtual environments and install app dependencies
RUN poetry config virtualenvs.create false && \
  poetry config virtualenvs.in-project false && \
  poetry install 

FROM gcr.io/distroless/python3-debian11 AS runtime

# Set the PYTHONPATH to the deps directory
ENV PYTHONPATH="/usr/bin/deps"

# Copy dependencies from the build stage
COPY --from=build /usr/lib/python3.9/site-packages/ /usr/bin/deps/

# Copy uvicorn executable from the build stage
COPY --from=build /usr/bin/uvicorn /usr/bin/uvicorn

WORKDIR /app
# Copy the rest of the project over
COPY ./app ./app

EXPOSE 80

ENTRYPOINT ["/usr/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80"]

