"""Generate inspectable overlays and a local technical report from actual runs."""
import html
import importlib.metadata
import json
from pathlib import Path
import statistics
import subprocess
import sys

import cv2
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg
import numpy as np

BASE = Path(__file__).parent / "results"
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
SMALL = ImageFont.truetype(FONT, 18)
LARGE = ImageFont.truetype(FONT, 25)
COMMON = ["left_shoulder_1_joint", "right_shoulder_1_joint", "left_forearm_joint", "right_forearm_joint",
    "left_hand_joint", "right_hand_joint", "left_upLeg_joint", "right_upLeg_joint", "left_leg_joint", "right_leg_joint", "left_foot_joint", "right_foot_joint"]
MP_IDS = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
LINKS = [(0,1),(0,2),(2,4),(1,3),(3,5),(0,6),(1,7),(6,7),(6,8),(8,10),(7,9),(9,11)]
COLORS = [(92,222,244),(255,191,87),(171,132,255),(255,110,142),(113,226,162)]


def load(name):
    result = json.loads((BASE / f"{name}.json").read_text())
    return result["frames"] if isinstance(result, dict) and "frames" in result else result


def pose_points(row, name):
    if not row["people"]:
        return []
    person = row["people"][0]
    if name == "vision":
        return [(person[k]["x"]*1280, person[k]["y"]*720, person[k]["confidence"]) for k in COMMON]
    return [(person[k]["x"]*1280, person[k]["y"]*720, min(person[k]["visibility"],person[k]["presence"])) for k in MP_IDS]


def draw_pose(frame, row, name, color):
    image = frame.copy()
    draw = ImageDraw.Draw(image)
    points = pose_points(row, name)
    if not points:
        return image
    for a,b in LINKS:
        if points[a][2] >= .5 and points[b][2] >= .5:
            draw.line([points[a][:2],points[b][:2]], fill=color, width=5)
    for x,y,c in points:
        if c >= .5:
            draw.ellipse((x-5,y-5,x+5,y+5),fill=color)
    return image


def encode(path, images, fps=8):
    images = iter(images)
    first = next(images)
    writer = imageio_ffmpeg.write_frames(str(path), first.size, fps=fps,
        codec="libx264", pix_fmt_in="rgb24", pix_fmt_out="yuv420p", quality=8,
        macro_block_size=2, output_params=["-movflags", "+faststart"], ffmpeg_log_level="error")
    writer.send(None)
    writer.send(np.asarray(first))
    for image in images:
        writer.send(np.asarray(image))
    writer.close()


def tracking_point(row, name):
    if name == "vision":
        t = row["tracks"][0]
        x,y,w,h = t["rect"]
        return ((x+w/2)*1280, (y+h/2)*720), t["confidence"] >= .5
    if name=='vision_flow':
        return row['points'][0],None
    return row["points"][0], row.get("valid",[True])[0]


def main():
    frames = load("frames")
    vision = load("vision")
    pose_names = [n for n in ["vision","mediapipe_lite","mediapipe_full"] if (BASE/f"{n}.json").exists()]
    pose_rows = {n:load(n) for n in pose_names}
    pose_stats = {}
    for name in pose_names:
        rows = pose_rows[name]
        latencies = [r["poseMS"] for r in rows[1:]]
        coverage = [sum(p[2]>=.5 for p in pose_points(r,name)) for r in rows]
        pose_stats[name] = {"detectedFrames":sum(bool(r["people"]) for r in rows),"frames":len(rows),
            "medianMSExcludingFirst":statistics.median(latencies),
            "firstFrameMS":rows[0]["poseMS"], "meanCommonPointsAboveThreshold":statistics.mean(coverage),
            "qualification":"Confidence coverage is not accuracy. Vision and MediaPipe scores are not calibrated to each other; backends differ."}
    def pose_images():
        for i, frame in enumerate(frames):
            original=Image.open(BASE/"frames"/frame["file"])
            canvas=Image.new("RGB",(640*len(pose_names),416),(16,22,32)); draw=ImageDraw.Draw(canvas)
            for j,name in enumerate(pose_names):
                panel=draw_pose(original,pose_rows[name][i],name,COLORS[j]).resize((640,360))
                canvas.paste(panel,(j*640,40));draw.text((j*640+16,8),name,fill=COLORS[j],font=LARGE)
            draw.text((12,397),f"source frame {i:02d} | {frame['seconds']:.3f}s | slowed display at 8fps | threshold 0.5 is NOT accuracy",fill='white',font=SMALL)
            yield canvas
    encode(BASE/"pose_comparison.mp4",pose_images())
    tracking_names = [n for n in ["vision","vision_flow","opencv_lk","opencv_csrt","bootstapir_256","bootstapir_corrected_256"] if (BASE/f"{n}.json").exists()]
    tracks={n:load(n) for n in tracking_names}
    ref=json.loads((BASE/"reference_points.json").read_text())
    checkpoints=ref["checkpoints"]
    errors={}
    for name in tracking_names:
        checked=[]
        for item in checkpoints:
            if 'corrected' in name and item['index'] in [18,42]:
                continue
            p, valid=tracking_point(tracks[name][item["index"]],name)
            distance=float(np.linalg.norm(np.array(p)-np.array(item["tip"])))
            checked.append({"index":item["index"],"errorPx":distance,"modelAccepts":None if valid is None else bool(valid)})
        errors[name]={"checks":checked,"meanApproximateErrorPx":statistics.mean(p["errorPx"] for p in checked),
            "qualification":"Approximate human visual checkpoints, one sample. Corrected runs exclude supplied anchors. Not dataset accuracy. Initial frame and ambiguous fast-swing frames excluded. Coordinates in 1280x720 analysis images."}
    def track_images():
        trails={name:[] for name in tracking_names}
        for i, frame in enumerate(frames):
            original=Image.open(BASE/"frames"/frame["file"])
            cols=3; rows=(len(tracking_names)+cols-1)//cols
            canvas=Image.new("RGB",(640*cols,424*rows),(16,22,32));draw=ImageDraw.Draw(canvas)
            for j,name in enumerate(tracking_names):
                panel=original.copy();d=ImageDraw.Draw(panel);point,valid=tracking_point(tracks[name][i],name)
                point=tuple(point);trails[name].append(point);col=COLORS[j%len(COLORS)]
                if valid is not False:
                    d.ellipse((point[0]-10,point[1]-10,point[0]+10,point[1]+10),outline=col,width=4)
                else:
                    d.line((point[0]-10,point[1]-10,point[0]+10,point[1]+10),fill=(255,82,100),width=4)
                    d.line((point[0]+10,point[1]-10,point[0]-10,point[1]+10),fill=(255,82,100),width=4)
                for check in checkpoints:
                    if check["index"]==i:
                        x,y=check["tip"];d.ellipse((x-14,y-14,x+14,y+14),outline='white',width=4)
                x=(j%cols)*640;y=(j//cols)*424
                canvas.paste(panel.resize((640,360)),(x,y+40));draw.text((x+14,y+8),name,fill=col,font=LARGE)
                quality='no quality score' if valid is None else 'gate passes' if valid else 'gate rejects'
                draw.text((x+12,y+402),f"source {i:02d} / {frame['seconds']:.3f}s | {quality}",fill='white',font=SMALL)
            if i==42:canvas.save(BASE/"tracking_comparison.jpg",quality=95)
            yield canvas
    encode(BASE/"tracking_comparison.mp4",track_images())
    if 'bootstapir_256' in tracks and 'bootstapir_corrected_256' in tracks:
        def semi_images():
            keys=['bootstapir_256','bootstapir_corrected_256']
            histories={key:[] for key in keys}
            for i,frame in enumerate(frames):
                original=Image.open(BASE/'frames'/frame['file'])
                canvas=Image.new('RGB',(1280,528),(16,22,32));draw=ImageDraw.Draw(canvas)
                for j,key in enumerate(keys):
                    panel=original.copy();d=ImageDraw.Draw(panel)
                    row=tracks[key][i];point,valid=tracking_point(row,key);point=tuple(point)
                    if valid:
                        histories[key].append(point)
                        if len(histories[key])>1:d.line(histories[key],fill=(113,226,162),width=4)
                        x,y=point;d.ellipse((x-10,y-10,x+10,y+10),outline=(113,226,162),width=4)
                    else:
                        histories[key]=[]
                        x,y=point;d.line((x-10,y-10,x+10,y+10),fill=(255,100,120),width=4);d.line((x+10,y-10,x-10,y+10),fill=(255,100,120),width=4)
                    manual=(i==0 or (j==1 and i in [18,42]))
                    if manual:
                        x,y=point;d.ellipse((x-17,y-17,x+17,y+17),outline='white',width=4)
                    panel=panel.crop((200,0,1200,720)).resize((640,461))
                    canvas.paste(panel,(j*640,38))
                    title='INITIAL SEED ONLY' if j==0 else 'WITH 2 USER CORRECTIONS'
                    draw.text((j*640+12,5),title,fill=(113,226,162),font=LARGE)
                    label='USER ANCHOR' if manual else 'NEEDS REVIEW' if not valid else 'TRACKING'
                    draw.text((j*640+12,502),f"f{i:02d} {frame['seconds']:.3f}s | {label}",fill='white',font=SMALL)
                if i==42:canvas.save(BASE/'semi_auto_demo.jpg',quality=95)
                yield canvas
        encode(BASE/'semi_auto_demo.mp4',semi_images())
    # Contact sheet for the highest-risk source frames; preserve blur for inspection.
    canvas=Image.new("RGB",(1280,4*248),(16,22,32));draw=ImageDraw.Draw(canvas)
    selected=[0,18,24,27,30,42,60,77]
    for j,i in enumerate(selected):
        original=Image.open(BASE/"frames"/frames[i]["file"])
        for k,name in enumerate(pose_names):
            panel=draw_pose(original,pose_rows[name][i],name,COLORS[k]).crop((400,0,1120,720)).resize((208,208))
            x=(j%2)*640+k*208;y=(j//2)*248
            canvas.paste(panel,(x,y+24));draw.text((x+4,y+5),f"{name} f{i}",fill=COLORS[k],font=SMALL)
    canvas.save(BASE/"pose_contact_sheet.jpg",quality=95)
    results={"sample":load("metadata"),"pose":pose_stats,"tracking":errors,
        "sampleCount":1,"analysisFrameSize":[1280,720],"executionPlatform":"macOS Apple Silicon, not iOS device",
        "scope":"iPhone + iPad, local only, semi-automatic tracking in v1"}
    for key in ["bootstapir","bootstapir_corrected","bootstapir_256","bootstapir_corrected_256"]:
        path=BASE/f"{key}.json"
        if path.exists():results[key+"Run"]={k:v for k,v in json.loads(path.read_text()).items() if k!='frames'}
    (BASE/"summary.json").write_text(json.dumps(results,ensure_ascii=False,indent=2))
    print(json.dumps(results,ensure_ascii=False,indent=2))


if __name__=="__main__":
    main()
