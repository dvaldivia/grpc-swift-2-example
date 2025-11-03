grpc-swift-2 Example
===

Had to create this as I had a hard time finding a simple example of grpc-swift-2 usage.

Project Structure
---
```
grpc-swift-2-example/
├── protos/
│   └── route_guide.proto         # gRPC service definition
├── server/                       # Go gRPC server implementation
│   └── main.go
└── client/                       # Swift gRPC client implementation
│   └── <xcode project>
└── buf.gen.yaml                  # Buf codegen config
```


## Generate Code

Install `buf` if you haven't already:

```bash
brew install bufbuild/buf/buf
```
Then generate the Swift and Go code from the proto definitions:

```bash
buf generate
```
This will create the necessary Swift files in the client project and Go files in the server project.

# Run the Server
Install Go runtime 
```bash
brew install go
```

then run the server like
```bash
(cd server && go run .)
```

# Run the Client

Open the Xcode project in the `client/` directory, build and run the client target.


# Why does this work?

I'm doing a workaround (Issue [#1797](https://github.com/apple/swift-protobuf/issues/1797)) where all the generated protobuf files are on a separate target (a separate framework). This way, both the client and server targets can depend on the same generated code without conflicts.

The grpc-protobuf taget has the MainActor attribute disabled, which avoids issues with async code generation in grpc-swift-2. 