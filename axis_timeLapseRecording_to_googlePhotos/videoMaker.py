import os
import cv2

def generateVideo(path, outfile):
    image_folder = '.'
    video_name = outfile
    os.chdir(path)
      
    images = [img for img in os.listdir(image_folder)
              if img.endswith(".jpg") or img.endswith(".jpeg") or img.endswith("png")]
     
  
    frame = cv2.imread(os.path.join(image_folder, images[0]))

    height, width, layers = frame.shape  
  
    video = cv2.VideoWriter(video_name, 0, 1, (width, height)) 
  
    # Appending
    for image in images: 
        video.write(cv2.imread(os.path.join(image_folder, image)))      
    
    cv2.destroyAllWindows() 
    video.release()

generateVideo('.', 'timeLapse.avi')
