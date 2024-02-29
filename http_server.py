from flask import Flask
from flask import request

app = Flask(__name__)

@app.route("/")
def default():
    return "Hello, World!"


# IOTEMBSYS: Implement the GET and POST handlers (either as separate routes or a single one)
latest_data = b''

@app.route("/data", methods=['GET', 'POST'])
def data():
    global latest_data
    if request.method == 'POST':
        print(request.get_data())
        latest_data = request.get_data()
        return ''
    else:
        return latest_data.decode('ascii')


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
