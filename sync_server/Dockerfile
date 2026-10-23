FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /syncserver .

FROM alpine:3.20
RUN adduser -D -H sync && mkdir /data && chown sync /data
COPY --from=build /syncserver /usr/local/bin/syncserver
USER sync
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["syncserver"]
