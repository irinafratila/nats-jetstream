# Use the official Golang image as the base
FROM golang:alpine

# Set environment variables
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

# Set working directory inside the container
WORKDIR /build

# Copy the entire application source
COPY . .

ARG GO_MAIN_PACKAGE
WORKDIR ${GO_MAIN_PACKAGE}

# Build the Go binary
RUN go build -o /app .

ENV CONSUMER_NUM="100"
ENV PUBLISHER_NUM="100"

# Run the application
CMD ["/app"]
