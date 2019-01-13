import os

processes = ['notepad.exe', 'chrome.exe', 'vlc.exe']
delay = 10

for process in processes:
    print("[+] Killing: {}".format(process))
    os.system("taskkill /f /im {}".format(process))


print("[*] Windows will restart in {} seconds".format(delay))
os.system("shutdown /r /t {}".format(delay))
