from flask import Flask
from flask import request
from flask_protobuf import flask_protobuf as FlaskProtobuf
import random
from idl.api_pb2 import OTAUpdateRequest, OTAUpdateResponse, StatusUpdateRequest, StatusUpdateResponse

import statsd

# Create the statsd client
server_stats = statsd.StatsClient("localhost", 8125)
device_stats = statsd.StatsClient("localhost", 8125, prefix="device")

app = Flask(__name__)
fb = FlaskProtobuf(app, parse_dict=True)

@app.route("/")
def default():
    server_stats.incr("default")
    return "Hello, World!"


@app.route("/status_update", methods=['POST'])
@fb(StatusUpdateRequest)
def status_update():
    server_stats.incr("status_update")
    print(request.data)
    device_id = request.data["deviceId"] if "deviceId" in request.data else "unknown"

    # Record device stats
    device_stats.incr(f"{device_id}.status_update")
    device_stats.gauge(f"{device_id}.boot_count", request.data["bootCount"])
    device_stats.gauge(f"{device_id}.uptime_ticks",int(request.data["uptimeTicks"]))
    device_stats.gauge(f"{device_id}.appStats.openCount",int(request.data["appStats"]["openCount"]))
    device_stats.gauge(f"{device_id}.appStats.ticks",int(request.data["appStats"]["ticks"]))

    resp = StatusUpdateResponse()
    resp.message = "Boot count: " + str(request.data["bootCount"])
    return resp.SerializeToString()
remoteUnlock = False

@app.route("/local_unlock", methods=['POST'])
def local_unlock():
    global remoteUnlock
    print(request.data)
    if(remoteUnlock == False):
        print("local unlock")
        random_number = random.randint(1, 255)
        print(random_number)
    else:
        remoteUnlock = False
        print("remote unlock")
        random_number = 0
    resp = StatusUpdateResponse()
    resp.message = str(random_number)
    return resp.SerializeToString()

@app.route("/remote_unlock", methods=['POST'])
def remote_unlock():
    print(request.data)
    global remoteUnlock
    remoteUnlock = True
    resp = StatusUpdateResponse()
    resp.message = "remote unlock success"
    return resp.SerializeToString()

@app.route("/ota", methods=['POST'])
@fb(OTAUpdateRequest)
def ota():
    server_stats.incr("ota")
    print(request.data)
    device_id = request.data["deviceId"] if "deviceId" in request.data else "unknown"
    device_stats.incr(f"{device_id}.ota")

    resp = OTAUpdateResponse()
    # This can be changed manually or through querying a datastore
    # You will want to check if the device already has the desired version!
    resp.path = "/6fc74ad3bbc7699957685cf1a0805f006d3cb1ff.signed.bin"
    return resp.SerializeToString()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
