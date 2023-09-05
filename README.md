# secure-container-image
![Hadolint](https://github.com/fivexl/secure-container-image/workflows/Hadolint/badge.svg?branch=main&event=push)


Collection of secure Docker container images

- Dockerfile.base. Example of minimal base image that could be used as a runtime base for apps that could be compliled into a binary (think golang, rust, c etc)

- Dockerfile.base-nodejs20-distroless-debian-11. Example of minimal base image that could be used as a runtime base for nodejs apps. This image is based on `gcr.io/distroless/nodejs20-debian11`.

- Dockerfile.base-python3-distroless-debian-11. Example of minimal base image that could be used as a runtime base for python3 apps. This image is based on `gcr.io/distroless/python3-debian11`.


Examples of application images that use above base images can be found in the `examples` folder:

- Dockerfile.goapp. Example of golang application that uses minimal base image from above and Docker multi-stage build to create secure golang docker-based application image.


- Dockerfile.node-app. Example of nodejs application that uses minimal base image: `ghcr.io/fivexl/secure-container-image-base-nodejs20-distroless-debian-11:latest` from above and Docker multi-stage build to create secure nodejs docker-based application image.

- Dockerfile.py-app-poetry. Example of python3 application that uses minimal base image: `ghcr.io/fivexl/secure-container-image-base-python3-distroless-debian-11:latest` from above and Docker multi-stage build to create secure python3 docker-based application image. This example uses poetry to manage python dependencies.

- Dockerfile.py-app-poetry-no-venv. Example of python3 application that uses minimal base image: `ghcr.io/fivexl/secure-container-image-base-python3-distroless-debian-11:latest` from above and Docker multi-stage build to create secure python3 docker-based application image. This example uses poetry to manage python dependencies. This example does not use virtual environment.

## Thoughts and considerations
You always have to balance security and productivity. While images described here provide above average level of security (nothing can be 100% secure), you would need to find a way to enable your developers to do their job when needed. By this, we mostly mean live troubleshooting. Since secure app images do not contain shell and debug tools, you won't even be able to exec into those running containers. But from time to time, developers need to. Of course, first put all effort into ensuring that you export logs and all possible telemetry from the application to outside so developers do not need to exec. Still, there are cases when there is no way around it. Thus we recommend building a second version of the same image using a different base (think Alpine) that could be used for debugging. The idea here is to have the possibility of swapping secure images to debug images when it is needed to troubleshoot the app. This type of swap should require elevated permissions to execute and should only be used when there is no other way.
