import cv2
import os
import time as t
from datetime import datetime

rtsp_url = 'rtsp://root:root@192.168.1.70:554/axis-media/media.amp'
google_photos_folder = "Axis_timeLapse"
google_api_key = 'client_id.json'
time_wait = 900

print('[+] Daemon started')
while True:
    try:
        c = cv2.VideoCapture(rtsp_url)
        ret, frame = c.read()
        c.release()
        if ret is not None: 
            f = datetime.today().strftime('%Y-%m-%d__%H_%M_%S')
            image = f'{f}.jpg'
            cv2.imwrite(image, frame)
        #today = filename=datetime.today().strftime('%Y-%m-%d')
        os.system(f'python3 upload.py --auth {google_api_key} --album "{google_photos_folder}" {image}')
        os.remove(image)
    except:
        pass
        print('Error...')
    print(f"[+] Waiting {time_wait} sec")
    t.sleep(time_wait)
    
    
