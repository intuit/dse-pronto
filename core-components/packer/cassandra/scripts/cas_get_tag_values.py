#!/usr/bin/env python3

import sys
from optparse import OptionParser
import boto3

if __name__ == "__main__":

    tag_found = False

    parser = OptionParser()
    parser.add_option("-n", "--node", dest="node", help="ip address of the node")
    parser.add_option("-t", "--tag", dest="tag", help="tag to query")
    parser.add_option("-r", "--region", dest="region", help="region", default="us-west-2")

    (options, args) = parser.parse_args(sys.argv)
    session = boto3.Session(region_name=options.region)

    client = session.client("ec2")
    response = client.describe_instances(Filters=[{ 'Name': "network-interface.addresses.private-ip-address", "Values": [options.node]}])
    for reservation in (response["Reservations"]):
        for instance in reservation["Instances"]:
            for tag in instance["Tags"]:
                if tag["Key"] == options.tag:
                    tag_found = True
                    print(tag["Value"])

    if not tag_found:
        print("Null")
