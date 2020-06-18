#!/usr/bin/env python3

##
# Objective: Helper class for EBS, ENI, and ASG managers

import botocore
import pprint
from awsretry import AWSRetry

pp = pprint.PrettyPrinter(indent=4)


class OpsEC2Manager:
    _session = None
    _client = None
    _resource = None
    _pp = None

    def __init__(self, session, client, resource):
        self._session = session
        self._client = client
        self._resource = resource
        self._pp = pprint.PrettyPrinter(indent=4)

    @AWSRetry.backoff(tries=20, delay=2, backoff=1.5)
    def get_instances(self, filters):
        try:
            pp.pprint(filters)
            response = self._client.describe_instances(Filters=filters)
            return response
        except botocore.exceptions.ClientError as e:
            raise e

    @AWSRetry.backoff(tries=20, delay=2, backoff=1.5)
    def get_volumes_by_id(self, vol_id):
        try:
            response = self._client.describe_volumes(VolumeIds=[vol_id])
            if len(response["Volumes"]) == 1:
                return response["Volumes"][0]
            return response
        except botocore.exceptions.ClientError as e:
            raise e

    def get_host_names_from_ips(self, node_list):
        node_names = []
        filters = [{'Name': "network-interface.addresses.private-ip-address", "Values": node_list}]
        response = self.get_instances(filters)

        for reservation in (response["Reservations"]):
            for instance in reservation["Instances"]:
                inst = self._resource.Instance(instance["InstanceId"])
                for tag in inst.tags:
                    if tag["Key"] == "Name":
                        if not tag["Value"] in node_names:
                            node_names.append(tag["Value"])
        return node_names

    def get_hosts(self, node_list, match_by_name):
        """
            Inputs
             :param account :
             :param cluster : used to query the EC2s with cluster tag
             :param node_list :
             :param match_by_name :
             :return: list of EC2s which are in available state
        """
        hosts = []
        filters = [
            {'Name': "tag:pool", "Values": ["opscenter"]},
            {'Name': "instance-state-name", "Values": ["running"]}
        ]

        if match_by_name:
            node_names = self.get_host_names_from_ips(node_list)

            print("---- Node names: ----------")
            self._pp.pprint(node_names)

            if len(node_names):
                filters.append({'Name': "tag:Name", "Values": node_names})
        else:
            # match by ip
            if len(node_list):
                filters.append({'Name': "network-interface.addresses.private-ip-address", "Values": node_list})

        response = self.get_instances(filters)
        for reservation in (response["Reservations"]):
            for instance in reservation["Instances"]:
                inst = self._resource.Instance(instance["InstanceId"])
                inst_details = {"id": instance["InstanceId"], "eth1": None, "az": inst.placement["AvailabilityZone"]}

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

                block_devices = []
                for block_device in inst.block_device_mappings:
                    volume_id = block_device["Ebs"]["VolumeId"]
                    volume = self.get_volumes_by_id(volume_id)
                    device_details = {"name": block_device["DeviceName"], "volume_id": volume_id,
                                      "volume_type": volume["VolumeType"], "volume_size": volume["Size"]}
                    block_devices.append(device_details)

                inst_details["block_devices"] = block_devices
                hosts.append(inst_details)

        return hosts
