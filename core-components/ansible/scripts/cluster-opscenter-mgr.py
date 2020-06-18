#!/usr/bin/env python3

import json
import requests
import time
import sys
import base64
from urllib3.exceptions import InsecureRequestWarning
from requests_toolbelt.utils import dump
import uuid
import  os


class OpsCenterMgr:
    """Class that manages access to datastax opscneter resources"""

    def __init__(self, url):
        self._url = url
        self.session_id = None
    def login(self):
        if not self.session_id:
            admin_pwd = os.getenv('OPS_ADMIN_PWD')
            if admin_pwd == None or len(admin_pwd) == 0:
                admin_pwd = "admin"
            creds = { "username":"admin","password": admin_pwd}
            headers = {'Content-Type' : 'application/json'}
            r = requests.post(f"{self._url}/login", headers=headers, data=json.dumps(creds), verify = False)
            data = dump.dump_all(r)
            #print(data.decode('utf-8'))
            print(f"Login status {r.status_code}")
            data = r.json()
            if "sessionid" in data.keys():
                self.session_id = data["sessionid"]
                print("Logged to opscenter successfully")
            else:
                print("unable to login to opscenter")
        return self.session_id
    
    def logout(self):
        result = None
        # curl -X GET -H 'opscenter-session: 1948fa886a91a1905a29192cf209114d' 'http://localhost:8888/logout'
        if self.session_id:
            print(f"Logging out for the session: {self.session_id}")
            headers = { "opscenter-session": self.session_id, 'Content-Type' : 'application/json'}
            r = requests.get(f"{self._url}/logout", headers=headers, verify = False)
            result = r.status_code
            print(f"Logout status {result}")
            self.session_id = None
        return result
    
    def add_alerts(self, cluster, target_alerts):
        result = None
        if self.session_id:
            #print(f"Adding alerts for : {self.session_id}")
            headers = { "opscenter-session": self.session_id, 'Content-Type' : 'application/json'}
            # get the existing rules and add to list if it not already in the list
            r = requests.get(f"{self._url}/{cluster}/alert-rules", headers=headers, verify = False)
            alerts = r.json()
            #target_alerts = json.loads(target_alerts)
            for target_alert in  target_alerts:
                print(target_alert)
                deploy_alert = True
                for a in alerts:
                    same_alert = True
                    #print(a)
                    for key in a.keys():
                        #print(key)
                        if key == "id":
                            continue
                        if key in target_alert:
                            if a[key] != target_alert[key]:
                                same_alert = False
                                break
                    if same_alert:
                        print(f"Found {a['id']} to be same as target alert")
                        deploy_alert = False
                        result = 200
                if deploy_alert:
                    r = requests.post(f"{self._url}/{cluster}/alert-rules", headers=headers, data=json.dumps(target_alert), verify = False)
                    result = r.status_code
                    print(f"Add alert status {result}")
        return result

    def add_dashboards(self, cluster, target_dashboards):
        result = None
        if self.session_id:
            #print(f"Adding alerts for : {self.session_id}")
            headers = { "opscenter-session": self.session_id, 'Content-Type' : 'application/json'}
            # get the existing rules and add to list if it not already in the list
            r = requests.get(f"{self._url}/{cluster}/rc/dashboard_presets/", headers=headers, verify = False)
            dashboards = r.json()
            #print(dashboards)
            for target_db in  target_dashboards:
                #print(target_db)
                print(f"Adding dashboard: {target_db['name']}")
                dashboard_id = None
                for key in dashboards:
                    db = dashboards[key]
                    #print(db)
                    if db["name"] == target_db["name"]:
                        dashboard_id = key
                        break

                if dashboard_id:
                    print(f"Found dashboard with same name {target_db['name']} using {dashboard_id} as preset_id")
                else:
                    dashboard_id = uuid.uuid1()
                    print(f"generated new id: {dashboard_id}")

                # Added the dashboard    
                r = requests.put(f"{self._url}/{cluster}/rc/dashboard_presets/{dashboard_id}", headers=headers, data=json.dumps(target_db), verify = False)
                result = r.status_code
                print(f"Add dashboard status {result}")

        return result

    def update_bestpractice_rule_schedules(self, cluster, rules):
        result = None
        if self.session_id:
            #print(f"Adding alerts for : {self.session_id}")
            headers = { "opscenter-session": self.session_id, 'Content-Type' : 'application/json'}
            # get the existing rules and add to list if it not already in the list
            r = requests.get(f"{self._url}/{cluster}/job-schedules/", headers=headers, verify = False)
            jobs = r.json()
            rules_to_process = [r["rule"] for r in rules if r["enabled"] == 0]
            print(rules_to_process)
            print(len(rules_to_process))
            for job in  jobs:
                if job["job_params"]["type"] == "best-practice":
                    if job["job_params"]["rules"][0] in rules_to_process:
                        print(f"Deleting job {job['id']} for rule {job['job_params']['rules'][0]} ")
                        r = requests.delete(f"{self._url}/{cluster}/job-schedules/{job['id']}", headers=headers, verify = False)
                        result = r.status_code
        return result


if __name__ == "__main__":
    from optparse import OptionParser
    import pprint
    import json
    import sys

    parser = OptionParser()
    parser.add_option("-o", "--operation", dest="operation", help="add_alerts | add_dashboards | update_bestpractices",default="add_alerts")
    parser.add_option("-u", "--url", dest="url", help="url for opscenter")
    parser.add_option("-c", "--cluster", dest="cluster", help="target cluster")
    parser.add_option("-p", "--payload_file", dest="payload_file", help="json payload for the dashboard or alert")
    # Suppress only the single warning from urllib3 needed.
    requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

    pp = pprint.PrettyPrinter(indent=4)
    (options, args) = parser.parse_args(sys.argv)
    pp.pprint(options)
    payload = None
    with open(options.payload_file) as json_file:
        payload = json.load(json_file)
   
    opsMgr = OpsCenterMgr(options.url)
    # Login
    session_id = opsMgr.login()
    #cluster = "dse-ssarma-ops-storage"
    if options.operation == "add_alerts":
        opsMgr.add_alerts(options.cluster, payload)
    elif options.operation == "add_dashboards":
        opsMgr.add_dashboards(options.cluster,payload)
    elif options.operation == "update_bestpractices":
        opsMgr.update_bestpractice_rule_schedules(options.cluster,payload)

    # Logout
    #opsMgr.logout()