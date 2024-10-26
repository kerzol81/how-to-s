import requests
from datetime import datetime, timedelta

# credentials
jira_url = "https://XZY.atlassian.net"
api_token = "API TOKEN string"
headers = {
    "Authorization": f"Bearer {api_token}",
    "Content-Type": "application/json"
}


today = datetime.utcnow()
past_date = today - timedelta(days=60)


response = requests.get(f"{jira_url}/rest/api/3/users/search?maxResults=1200", headers=headers)
users = response.json()


for user in users:
    last_active = user.get('lastActive')
    if last_active:
        last_active_date = datetime.strptime(last_active, '%Y-%m-%dT%H:%M:%S.%fZ')
        if last_active_date < past_date:
            
            # DEACTIVATE users SINCE JIRA doesnt allow USER deletion
            account_id = user['accountId']
            requests.put(f"{jira_url}/rest/api/3/user?accountId={account_id}",
                         headers=headers, json={"active": False})
