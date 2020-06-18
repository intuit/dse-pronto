#!/usr/bin/env python3

from optparse import OptionParser
import sys
import os
from os.path import *
import boto3
import botocore
import pprint

import yaml
from yaml import load, dump

try:
    from yaml import CLoader as Loader, CDumper as Dumper
except ImportError:
    from yaml import Loader, Dumper

pp = pprint.PrettyPrinter(indent=4)


class casHostManager:
    """Class that manages the ansible-hosts for Cassandra nodes"""
    _session = None
    _client = None
    _resource = None

    def __init__(self, profile,region):
        self._session = boto3.Session(profile_name=profile,region_name=region)
        self._client = self._session.client('ec2')
        self._resource = self._session.resource('ec2')
        self._pp = pprint.PrettyPrinter(indent=4)

    def get_Hosts(self, account, cluster):
        """
            Inputs
             :param account : used to query the ENIs with account tag
             :param cluster : used to query the ENIs with cluster tag
             :return: list of ENIs which are in available state
        """
        hosts = []

        response = self._client.describe_instances(Filters=[
            { 'Name': "tag:ClusterName", "Values": [cluster]},
            { 'Name': "tag:Account", "Values": [account]},
            { 'Name': "instance-state-name", "Values": ["running"]}
        ])
        for reservation in (response["Reservations"]):
            for instance in reservation["Instances"]:
                inst_details = {}
                inst_details["id"] = instance["InstanceId"]
                inst = self._resource.Instance(instance["InstanceId"])

                for t in inst.tags:
                    if t["Key"] == "Name":
                        inst_details["name"] = t["Value"]
                    if t["Key"] == "active_interface":
                        inst_details["active_interface"] = t["Value"]
                    if t["Key"] == "aws:autoscaling:groupName":
                        inst_details["asg"] = t["Value"]
                for a in inst.network_interfaces_attribute:
                    if a["Attachment"]["DeviceIndex"] == 0:
                        inst_details["eth0"] = a["PrivateIpAddress"]
                    if a["Attachment"]["DeviceIndex"] == 1:
                        inst_details["eth1"] = a["PrivateIpAddress"]
                inst_details["zone"] = inst.placement["AvailabilityZone"]

                hosts.append(inst_details)
        return hosts

    def generateAnsibleHost(self, hosts, host_file):
        ansible_data = {}
        seed_nodes = {}
        non_seed_nodes = {}
        inactive_nodes = {}

        for host in hosts:

            pp.pprint(host)

            active_interface = host["active_interface"]
            active_ip = host[active_interface]
            name = "%s:%s" %(host["name"], active_interface)
            if active_interface == "eth0":
                inactive_nodes[active_ip] = name
            else:
                if "non-seed" not in host["name"]:
                    seed_nodes[active_ip] = name
                else:
                    non_seed_nodes[active_ip] = name

        ansible_data["seeds"] = {}
        ansible_data["seeds"]["hosts"] = seed_nodes

        ansible_data["non-seeds"] = {}
        ansible_data["non-seeds"]["hosts"] = non_seed_nodes

        ansible_data["inactive"] = {}
        ansible_data["inactive"]["hosts"] = inactive_nodes

        #pp.pprint(ansible_data)

        with open(host_file, 'w') as stream:
            for group in ansible_data.keys():
                stream.write("[%s]\n" %(group))
                for host in ansible_data[group]["hosts"].keys():
                    stream.write("%s\n" %(host))
            stream.close()


if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option("-f", "--file", dest="file", help="host file")
    parser.add_option("-p", "--aws_profile", dest="aws_profile", help="AWS profile")
    parser.add_option("-a", "--account", dest="account", help="account")
    parser.add_option("-c", "--cluster", dest="cluster", help="cluster")
    parser.add_option("-r", "--region", dest="region", help="region", default="us-west-2")

    (options, args) = parser.parse_args(sys.argv)

    casHostMgr = casHostManager(options.aws_profile, options.region)

    nodes = casHostMgr.get_Hosts(options.account, options.cluster)
    casHostMgr.generateAnsibleHost(nodes, options.file)

    sys.exit(0)
