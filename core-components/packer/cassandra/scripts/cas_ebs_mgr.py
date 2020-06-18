#!/usr/bin/env python3

##
# Objective: Attach storage EBS volumes to EC2 instances, if the instances do not
#            have specified number of volumes of the requested type
#
#    Inputs:
#         aws_profile:       profile to query AWS environment for attached storage for the EC2 instances
#         pvt_ip_list:       List of private_ips of the EC2 instances
#         number_of_volumes:
#         volume_type:
#         volume_size:
#    Output:
#         instance-id:       {volumes} listing in a json format

from optparse import OptionParser
import sys
import boto3
import botocore
import pprint
import time
from awsretry import AWSRetry

from cas_ec2_mgr import CasEC2Manager

pp = pprint.PrettyPrinter(indent=4)


class CasEBSManager:
    """Class that manages the ebs volumes for the Cassandra nodes"""
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

    @AWSRetry.backoff(tries=20, delay=2, backoff=1.5)
    def get_volumes(self, filters):
        try:
            response = self._client.describe_volumes(Filters=filters)
            return response
        except botocore.exceptions.ClientError as e:
            raise e

    def get_next_device_name(self, instance):
        # find the max of the available device_names
        names = [x["name"] for x in instance["block_devices"]]
        max_device = max(names)

        if max_device[-1].isdigit():
            max_device = max_device[:-1]

        next_device = "%s%s" % (max_device[:-1], chr(ord(max_device[-1]) + 1))
        return next_device

    def get_hosts(self, account, cluster, node_list, match_by_name):
        return self._ec2_mgr.get_hosts(account, cluster, node_list, match_by_name)

    def detach_from_instance(self, hosts, interface):
        active_hosts = [x for x in hosts if x["active_interface"] == interface]

        print("---- Active hosts: --------")
        pp.pprint(active_hosts)

        for h in active_hosts:
            vol_to_detach = [x for x in h["block_devices"] if (x["name"] != "/dev/sda1" and x["name"] != "/dev/xvda")]

            print("---- Vol to detach: -------")
            pp.pprint(vol_to_detach)

            for v in vol_to_detach:
                self._client.detach_volume(VolumeId=v["volume_id"], Device=v["name"], InstanceId=h["id"], Force=True)
                waiter = self._client.get_waiter("volume_available")
                waiter.wait(VolumeIds=[v["volume_id"]])

    def get_volume_by_tags(self, az, volume_type, volume_size, tags):
        # build Filters

        pp.pprint(tags)

        additional_tags = [{'Name': "tag:%s" % (x['Key']), 'Values': [x['Value']]} for x in tags]
        filter_tags = [
            {'Name': "availability-zone", "Values": [az]},
            {'Name': "size", "Values": [str(volume_size)]},
            {'Name': "status", "Values": ["available"]},
            {'Name': "volume-type", "Values": [volume_type]}
        ]

        print("---- GetVolumes filters: --")
        pp.pprint(filter_tags + additional_tags)

        response = self.get_volumes(filter_tags + additional_tags)

        print("---- GetVolumes resp: -----")
        pp.pprint(response)

        # using above filters, should find exactly 0 or 1 volumes
        vol = None
        if len(response["Volumes"]) == 1:
            vol = response["Volumes"][0]
        elif len(response["Volumes"]) > 1:
            print("Expected exactly 1 volume, found {0}".format(len(response["Volumes"])))
            sys.exit(1)

        return vol

    def attach_volumes(self, hosts, number_of_volumes, volume_type, volume_size, extra_comments, iops, interface):
        volume_ids = []
        waiter_volume_available = self._client.get_waiter('volume_available')

        active_hosts = [x for x in hosts if x["active_interface"] == interface]

        print("---- Active hosts: --------")
        self._pp.pprint(active_hosts)

        for instance in active_hosts:
            current_vols = 0

            # count existing volumes and create more as needed.
            for device in instance["block_devices"]:
                if device["volume_size"] == volume_size and device["volume_type"] == volume_type:
                    if device["name"] != "/dev/sda1" and device["name"] != "/dev/xvda":
                        current_vols = current_vols + 1

            if current_vols < number_of_volumes:
                vol_to_add = number_of_volumes - current_vols
                print("Need to add %d volumes to %s" % (vol_to_add, instance["id"]))
                purpose = extra_comments[0]["Value"]

                for i in range(0, vol_to_add):
                    device_name = self.get_next_device_name(instance)

                    # These tags are used to find the volume. Don't change this list.
                    identifying_tags = [
                             {'Key': 'instance-name', 'Value': instance["name"]},
                             {'Key': 'device_name', 'Value': device_name},
                             {'Key': 'Name', 'Value': "%s-%s-%d" % (instance["name"], purpose, i)}
                    ]

                    # This is the full tag spec.
                    tags = [
                             {'Key': 'instance-name', 'Value': instance["name"]},
                             {'Key': 'device_name', 'Value': device_name},
                             {'Key': 'Name', 'Value': "%s-%s-%d" % (instance["name"], purpose, i)}
                           ]
                    tag_spec = [{'ResourceType': 'volume', "Tags": tags + extra_comments}]

                    print("---- Tag spec: ------------")
                    self._pp.pprint(tag_spec)

                    vol = self.get_volume_by_tags(instance["az"], volume_type, volume_size, identifying_tags)

                    print("---- Volumes found: -------")
                    self._pp.pprint(vol)
                    new_volume = None
                    if vol is None:
                        if volume_type == "gp2":
                            new_volume = self._client.create_volume(AvailabilityZone=instance["az"],
                                                                    Encrypted=True,
                                                                    VolumeType=volume_type,
                                                                    Size=volume_size,
                                                                    TagSpecifications=tag_spec)
                        elif volume_type == "io1":
                            new_volume = self._client.create_volume(AvailabilityZone=instance["az"],
                                                                    Encrypted=True,
                                                                    VolumeType=volume_type,
                                                                    Iops=iops,
                                                                    Size=volume_size,
                                                                    TagSpecifications=tag_spec)
                        else:
                            print("Unknown volume_type [%s]" % volume_type)
                        if new_volume:
                            vol_id = new_volume["VolumeId"]
                        else:
                            print("Failed to create a new_volume")
                    else:
                        vol_id = vol["VolumeId"]
                        print("Attaching tags to existing volume..")
                        _ = self._client.create_tags(
                            DryRun=False,
                            Resources=[vol_id],
                            Tags=tag_spec[0]['Tags']
                        )

                    print('---- Attach volume {}'.format(vol_id))
                    try:
                        print('Entering wait...')
                        waiter_volume_available.wait(
                            VolumeIds=[
                                vol_id
                            ]
                        )
                        print('Wait successful!')
                    except botocore.exceptions.WaiterError as e:
                        self._client.delete_volume(VolumeId=vol_id)
                        sys.exit('ERROR: {}'.format(e))
                    inst = self._resource.Instance(instance["id"])
                    inst.attach_volume(
                        VolumeId=vol_id,
                        Device=device_name
                    )
                    instance["block_devices"].append(
                        {"name": device_name, "volume_type": volume_type, "volume_size": volume_size,
                         "volume_id": vol_id})
                    volume_ids.append(vol_id)
                    waiter = self._client.get_waiter("volume_in_use")
                    waiter.wait(VolumeIds=[vol_id])
                    time.sleep(15)
        return volume_ids


if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option("-a", "--account", dest="account", help="DP account")
    parser.add_option("-r", "--region", dest="region", help="region")
    parser.add_option("-e", "--env", dest="env", help="env")
    parser.add_option("-c", "--cluster", dest="cluster", help="cluster")
    parser.add_option("-l", "--pvt_ip_list", dest="pvt_ip_list", help="List of private ips")
    parser.add_option("-n", "--number_of_volumes", dest="number_of_volumes", type="int",
                      help="Number of volumes to attach")
    parser.add_option("-t", "--volume_type", dest="volume_type", help="Type of EBS volume", default="gp2")
    parser.add_option("-s", "--volume_size", dest="volume_size", type="int", help="Size of EBS volume in MiB")
    parser.add_option("-x", "--comments", dest="comments", help="Tag list to indentify volume")
    parser.add_option("-i", "--iops", dest="iops", help="provisioned iops", type="int")
    parser.add_option("-o", "--operation", dest="operation", help="operation can be attach or detach", type="string",
                      default="attach")
    parser.add_option("-f", "--active_interface", dest="active_interface", help="can be eth0 or eth1", type="string",
                      default="eth0")

    (options, args) = parser.parse_args(sys.argv)
    pp = pprint.PrettyPrinter(indent=4)

    casEBSMgr = CasEBSManager(options.region)

    pvt_ip_list = []
    if options.pvt_ip_list == "":
        print("You need to pass the list of private_ips to filter by")
        sys.exit()
    pvt_ip_list = options.pvt_ip_list.rstrip(',').split(",")

    if options.operation == "attach":
        instance_details = casEBSMgr.get_hosts(options.account, options.cluster, pvt_ip_list, True)

        print("---- Instance details: ----")
        pp.pprint(instance_details)

        if options.number_of_volumes > 0 and options.volume_type != "" and options.volume_size > 0:
            comments = [{"Key": x.split(":")[0], "Value": x.split(":")[1]} for x in options.comments.split(",")]
            vol_ids = casEBSMgr.attach_volumes(instance_details, options.number_of_volumes, options.volume_type,
                                               options.volume_size, comments, options.iops, options.active_interface)

            print("---- New volume IDs: ------")
            pp.pprint(vol_ids)
        else:
            print("Provide a valid number_of_volumes, volume_type and volume_size")
    elif options.operation == "detach":
        instance_details = casEBSMgr.get_hosts(options.account, options.cluster, pvt_ip_list, False)
        print("Detaching the EBS volumes from instances")
        casEBSMgr.detach_from_instance(instance_details, "eth1")
