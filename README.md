# NSP JSON to JIRA

> Generate Jira tickets from reported npm vulnerabilities

The NSP JSON to JIRA script takes the output of `nsp check --reporter json` and opens JIRA bugs with appropriate severity and titles. The description links back to the vulnDB for more information.

The script uses two JIRA custom fields to record the vulnID and the path, and does not recreate tickets if one already exists with same vulnID path.

# How do I use it?

### 1. Add custom fields to your JIRA project

You'll need two custom fields setup for relevant NSP metadata. (You can setup a custom field in JIRA by going to Settings --> Issues --> Custom Fields --> Add Custom Field).

The two fields you'll need are (you can also customize these field names within the `nsp-to-jira.sh` script):

* `nsp-vuln-id` This should be a "Text Field Single Line"
* `nsp-path` This should be a "Text Field Single Line"

### 2. Rename the provided [`.jirarc`](jirarc-template.txt) template to `.jirarc`, populate the variables and place it in your project directory.

```sh
$ mv `.jirac-template.txt` .jirarc
```

In the `.jirarc` file, you will need to set three variables:

* `JIRA_USER` A valid user for your JIRA project
* `JIRA_PASSWORD` An api key for the provided user. See [here](https://confluence.atlassian.com/cloud/api-tokens-938839638.html).
* `BASE_JIRA_URL` A URL pointing to the JIRA instance
* `JIRA_PROJECT_NAME` The name of the JIRA project where you would like vulnerability bugs filed

### 3. Run the script by passing the results of `nsp check --reporter json`

```sh
$ cd ~/project
$ nsp check --reporter json > nsp-test.json
$ nsp-to-jira.sh nsp-test.json
```

### 4. Open your JIRA project and triage away!

## License

[License: Apache License, Version 2.0](LICENSE)

## Credit

This project was forked from [snyk-to-jira](https://github.com/snyk/snyk-to-jira) and was adjusted to work with [nsp](https://github.com/nodesecurity/nsp) instead of Snyk.
Snyk deserves the credit for this and I recommend checking out their excellent service: https://snyk.io
