import socketserver

class MyTCPHandler(socketserver.StreamRequestHandler):
    def handle(self):
        print("TCP handler")

        # self.request is the TCP socket connected to the client
        self.data = self.rfile.readline().strip()
        print("{} sent:".format(self.client_address[0]))
        print(self.data)
        # just send back the same data, but upper-cased
        self.request.sendall(self.data.upper())

if __name__ == "__main__":
    # The host works differently depending on the platform, so the
    # best bet is to leave it blank. If you have having trouble
    # connecting, you can try "localhost" or "127.0.0.1"
    HOST, PORT = "", 4242
    print("The server is running")

    # Create the server, binding to localhost on port 9999
    with socketserver.TCPServer((HOST, PORT), MyTCPHandler) as server:
        # Activate the server; this will keep running until you
        # interrupt the program with Ctrl-C
        server.serve_forever()
    
    print("The server is shutting down")
