ARG DEBIAN_SLIM_TAG=11.7-slim
ARG DISTROLESS_TAG=@sha256:69ae7f133d33faab720af28e78fb45707b623bcbc94ae02a07c633bf053f4b40

FROM debian:${DEBIAN_SLIM_TAG} AS build

ARG POETRY_VERSION=1.6.1
ARG LIBPYTHON3_VERSION=3.9.2-3
ARG GCC_VERSION=4:10.2.1-1
ARG PYTHON3_VERSION=3.9.2-3
ARG PYTHON3_PIP_VERSION=20.3.4-4+deb11u1

RUN apt-get update && \
  apt-get install --no-install-suggests --no-install-recommends --yes python3=${PYTHON3_VERSION} python3-pip=${PYTHON3_PIP_VERSION} gcc=${GCC_VERSION} libpython3-dev=${LIBPYTHON3_VERSION} && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  pip install --no-cache-dir "poetry==${POETRY_VERSION}"

# Copy just the pyproject.toml and poetry.lock files to install dependencies
COPY pyproject.toml poetry.lock ./

# Disable the creation of virtual environments and install app dependencies
RUN poetry config virtualenvs.create false && \
  poetry config virtualenvs.in-project false && \
  poetry install 

FROM gcr.io/distroless/python3-debian11${DISTROLESS_TAG} AS runtime

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

