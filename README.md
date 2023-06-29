# secure-container-image
Collection of secure Docker container images

- Dockerfile.base. Example of minimal base image that could be used as a runtime base for apps that could be compliled into a binary (think golang, rust, c etc)
- Dockerfile.goapp. Example of golang application that uses minimal base image from above and Docker multi-stage build to create secure golang docker-based application image


## Thoughts and considerations
You always have to balance security and productivity. While images described here provide above average level of security (nothing can be 100% secure), you would need to find a way to enable your developers to do their job when needed. By this, we mostly mean live troubleshooting. Since secure app images do not contain shell and debug tools, you won't even be able to exec into those running containers. But from time to time, developers need to. Of course, first put all effort into ensuring that you export logs and all possible telemetry from the application to outside so developers do not need to exec. Still, there are cases when there is no way around it. Thus we recommend building a second version of the same image using a different base (think Alpine) that could be used for debugging. The idea here is to have the possibility of swapping secure images to debug images when it is needed to troubleshoot the app. This type of swap should require elevated permissions to execute and should only be used when there is no other way.
