#!/usr/bin/env python3

##
# Objective: Attach an elastic IP to EC2 instances, if not already present
#
#    Inputs:
#         account:    account ID
#         region:     region
#         cluster:    used to query ENIs via "cluster" tag
#         operation:  "attach" or "detach"
#         nodes:      comma delimited list of host IPs to operate on (default: "all")

from optparse import OptionParser
import sys
import boto3
import botocore
import pprint
import time
from cas_ec2_mgr import CasEC2Manager
from awsretry import AWSRetry

pp = pprint.PrettyPrinter(indent=4)


class CasNetworkInterfaceManager:
    """Class that manages the network interfaces for the Cassandra nodes"""
    _session = None
    _client = None
    _resource = None
    _ec2_mgr = None

    def __init__(self, region):
        self._session = boto3.Session(region_name=region)
        self._client = self._session.client('ec2')
        self._resource = self._session.resource('ec2')
        self._ec2_mgr = CasEC2Manager(self._session, self._client, self._resource)
        self._pp = pprint.PrettyPrinter(indent=4)

    def get_hosts(self, account, cluster, get_node_list, match_by_name):
        return self._ec2_mgr.get_hosts(account, cluster, get_node_list, match_by_name)

    @AWSRetry.backoff(tries=20, delay=2, backoff=1.5)
    def get_enis_from_filters(self, filters):
        try:
            response = self._client.describe_network_interfaces(Filters=filters)
            return response
        except botocore.exceptions.ClientError as e:
            raise e

    def get_enis(self, cluster, operation, nodes):
        """
            Inputs
             :param cluster : used to query the ENIs with cluster tag
             :param operation :
             :param nodes :
             :return : list of ENIs which are in available state
        """
        eni_filters = [
            {'Name': "tag:ClusterName", "Values": [cluster]}
        ]

        if operation == "attach":
            eni_filters.append({'Name': "status", "Values": ["available"]})
        else:
            eni_filters.append({'Name': "status", "Values": ["in-use"]})

        if len(nodes) != 0:
            node_names = self._ec2_mgr.get_host_names_from_ips(nodes)
            if len(node_names):
                name_filters = {'Name': "tag:Name", "Values": node_names}
                eni_filters.append(name_filters)
            else:
                eni_filters.append({'Name': "addresses.private-ip-address", "Values": nodes})

        print("---- ENI query filter: ----")
        self._pp.pprint(eni_filters)
        response = self.get_enis_from_filters(eni_filters)

        eni_list = [{"eni-id": x["NetworkInterfaceId"], "tags": x["TagSet"]} for x in response["NetworkInterfaces"]]
        print("---- ENI list: ------------")
        self._pp.pprint(eni_list)

        return eni_list

    def attach_enis(self, attach_eni_list, attach_hosts):
        self.attach_detach_enis(attach_eni_list, attach_hosts, "attach")

    def detach_enis(self, detach_eni_list, detach_hosts):
        self.attach_detach_enis(detach_eni_list, detach_hosts, "detach")

    def get_host_for_eni(self, eni, get_hosts, operation):
        print("---- Get host for ENI: ----")
        self._pp.pprint(eni)
        for t in eni["tags"]:
            if t["Key"] == "Name":
                eni_name = t["Value"]
        host = None
        matching_hosts = [x for x in get_hosts if x["name"] == eni_name]
        for h in matching_hosts:
            if host is None:
                host = h
            elif len(h["block_devices"]) > len(host["block_devices"]):
                host = h
        result = None
        if host:
            if operation == "attach" and ("active_interface" not in host or host["active_interface"] == "eth0"):
                result = host
            elif operation == "detach" and h["active_interface"] == "eth1":
                result = host
        return result

    def attach_detach_enis(self, attach_eni_list, attach_hosts, operation):
        attach_ids = []
        for eni in attach_eni_list:
            host = self.get_host_for_eni(eni, attach_hosts, operation)
            ni = self._resource.NetworkInterface(eni["eni-id"])

            print("---------------------------")
            if host:
                tags = []
                if operation == "attach":
                    print("Attaching eni [%s] to instance [%s]" % (eni["eni-id"], host["id"]))
                    r = ni.attach(DeviceIndex=1, InstanceId=host["id"])
                    time.sleep(20)
                    attach_ids.append(r["AttachmentId"])
                    # add a tag to the instance which indicates that eth1 is active_interface
                    tags = [{'Key': 'active_interface', 'Value': "eth1"}]
                elif operation == "detach":
                    print("Detaching eni: [%s] from instance: [%s] " % (eni["eni-id"], host["id"]))
                    time.sleep(20)
                    r = ni.detach()
                    # add a tag to the instance which indicates that eth0 is active_interface
                    tags = [{'Key': 'active_interface', 'Value': "eth0"}]
                    self._pp.pprint(r)

                if len(tags):
                    inst = self._resource.Instance(host["id"])
                    inst.create_tags(Tags=tags)

        return attach_ids


if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option("-r", "--region", dest="region", help="AWS region")
    parser.add_option("-a", "--account", dest="account", help="account")
    parser.add_option("-c", "--cluster", dest="cluster", help="cluster")
    parser.add_option("-o", "--operation", dest="operation", help="operation - attach|detach", default="attach")
    parser.add_option("-n", "--nodes", dest="nodes", help="ip address of the nodes", default="all")

    (options, args) = parser.parse_args(sys.argv)
    casNICMgr = CasNetworkInterfaceManager(options.region)

    node_list = []
    if options.nodes != "all":
        node_list = options.nodes.split(",")

    # Query the the available network-interfaces based on clusterName
    eni_list = casNICMgr.get_enis(options.cluster, options.operation, node_list)

    if options.operation == "attach":
        # Lookup the the instances based on name and if instance has only 1 interface attach the second one
        hosts = casNICMgr.get_hosts(options.account, options.cluster, node_list, True)

        print("---- Hosts: ---------------")
        pp.pprint(hosts)

        casNICMgr.attach_enis(eni_list, hosts)
    else:
        hosts = casNICMgr.get_hosts(options.account, options.cluster, node_list, False)
        casNICMgr.detach_enis(eni_list, hosts)
