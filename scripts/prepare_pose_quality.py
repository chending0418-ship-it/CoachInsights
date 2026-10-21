#!/usr/bin/env python3
"""Optional local QA: 60 fixed, human-labelled frames from 12 Penn Action test clips.
Requires numpy and opencv-python in a research Python environment. Not an App dependency.
Published test split only; no tuning or outcome-based sample selection.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, hashlib, json, struct, subprocess, zlib
import numpy as np
import cv2
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--set",choices=["diagnostic","acceptance"],default="acceptance")
parser.add_argument("--include-heavy",action="store_true",help="Optional comparison only; never an App resource")
args=parser.parse_args()
DIAGNOSTIC=["0001","0010","0013","0014","0025","0026","0168","0169","0170","0171","0172","0173"]
ACCEPTANCE=["0027","0028","0029","0030","0031","0033","0181","0182","0183","0184","0187","0189"]
IDS=DIAGNOSTIC if args.set=="diagnostic" else ACCEPTANCE
LABEL_REV="9758d0ac0df9b58f852ba3e76e1f32c4fa150f8d"
VIDEO_REV="ea509384e8bf8cc04c9591c88a60db6bd8e591eb"
LABELS=ROOT/"research/downloads/penn-labels"
VIDEOS=ROOT/"research/downloads/penn-videos"
OUTPUT=ROOT/"CoachInsightsTests/LocalFixtures"
for folder in [LABELS,VIDEOS,OUTPUT]: folder.mkdir(parents=True,exist_ok=True)

def elements(data):
    pos=0
    while pos+8<=len(data):
        tag,size=struct.unpack_from("<II",data,pos)
        if tag>>16:
            yield tag&65535,data[pos+4:pos+4+(tag>>16)];pos+=8
        else:
            payload=data[pos+8:pos+8+size]
            if len(payload)<size: raise ValueError("Truncated MAT element")
            yield tag,payload
            pos+=8+size+(0 if tag==15 else (-size)%8)

def loadmat(path):
    """Read the published numeric/character MAT v5 fields, checking compressed payloads."""
    out={}
    def parse(data):
        for kind,payload in elements(data):
            if kind==15: parse(zlib.decompress(payload))
            elif kind==14:
                values=list(elements(payload));flags=np.frombuffer(values[0][1],"<u4")
                dimensions=tuple(np.frombuffer(values[1][1],"<i4"));name=values[2][1].decode()
                types={1:"i1",2:"u1",3:"<i2",4:"<u2",5:"<i4",6:"<u4",7:"<f4",9:"<f8",12:"<i8",13:"<u8",16:"u1",17:"<u2"}
                kind,data=values[3];value=np.frombuffer(data,types[kind]).reshape(dimensions,order="F").squeeze()
                if (flags[0]&255)==4:value="".join(chr(int(x)) for x in np.atleast_1d(value).flat)
                out[name]=value
    data=path.read_bytes()
    if data[126:128]!=b"IM":raise ValueError("Unsupported MAT endian/version")
    parse(data[128:]);return out

def fetch(identifier):
    label=LABELS/f"{identifier}.mat";video=VIDEOS/f"{identifier}.mkv"
    for target,url in [(label,f"https://raw.githubusercontent.com/KacperM33/OKS_attack/{LABEL_REV}/penn-action-dataset/labels/{identifier}.mat"),
                       (video,f"https://huggingface.co/datasets/urzsi/Penn-Action-Lossless-MKV-Test-Subset/resolve/{VIDEO_REV}/videos/{identifier}-vis.mkv")]:
        if not target.exists():subprocess.run(["curl","-fL","--retry","3",url,"-o",str(target)],check=True)

with ThreadPoolExecutor(max_workers=6) as executor:list(executor.map(fetch,IDS))
if args.include_heavy:
    heavy=OUTPUT/"pose_landmarker_heavy.task"
    expected="64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b"
    if not heavy.exists():subprocess.run(["curl","-fL","--retry","3","https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task","-o",str(heavy)],check=True)
    assert hashlib.sha256(heavy.read_bytes()).hexdigest()==expected
# The published evaluation code corrects Penn's right/left column order:
# https://github.com/KacperM33/OKS_attack/blob/9758d0ac0df9b58f852ba3e76e1f32c4fa150f8d/oks_tools/measures.py#L239
names=["head","rightShoulder","leftShoulder","rightElbow","leftElbow","rightWrist","leftWrist","rightHip","leftHip","rightKnee","leftKnee","rightAnkle","leftAnkle"]
samples=[];provenance=[]
for identifier in IDS:
    label=LABELS/f"{identifier}.mat";video=VIDEOS/f"{identifier}.mkv";data=loadmat(label)
    assert int(data["train"])==-1 and data["action"] in ["baseball_pitch","baseball_swing"]
    labelHeight,labelWidth,nframes=map(int,data["dimensions"])
    capture=cv2.VideoCapture(str(video));assert int(capture.get(cv2.CAP_PROP_FRAME_COUNT))==nframes
    width=int(capture.get(cv2.CAP_PROP_FRAME_WIDTH));height=int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    assert abs(width-labelWidth)<=1 and abs(height-labelHeight)<=1
    sx=width/labelWidth;sy=height/labelHeight
    # Mirrors even-sized video dimensions; label coordinates are scaled explicitly (at most 1 pixel).
    # One fixed actor region for the whole clip, modelling a user's manual selection.
    bbox=(data["bbox"]-1)*np.array([sx,sy,sx,sy]);left,top=bbox[:,:2].min(axis=0);right,bottom=bbox[:,2:].max(axis=0)
    pad=(bottom-top)*0.05;left=max(0,left-pad);top=max(0,top-pad);right=min(width,right+pad);bottom=min(height,bottom+pad)
    region=[left/width,top/height,(right-left)/width,(bottom-top)/height]
    for index in np.linspace(0,nframes-1,5).round().astype(int):
        capture.set(cv2.CAP_PROP_POS_FRAMES,int(index));ok,frame=capture.read();assert ok and frame.shape[:2]==(height,width)
        filename=f"penn-{identifier}-{index:06d}";cv2.imwrite(str(OUTPUT/(filename+".png")),frame)
        points=[dict(name=name,x=float((data["x"][index,j]-1)*sx),y=float((data["y"][index,j]-1)*sy),visible=bool(data["visibility"][index,j])) for j,name in enumerate(names) if j>0]
        samples.append(dict(clip=identifier,sport=data["action"],file=filename,index=int(index),width=width,height=height,region=region,
                            bodyHeight=float(bbox[index,3]-bbox[index,1]),points=points))
    provenance.append(dict(clip=identifier,action=data["action"],split="published test (-1)",
        labelSHA256=hashlib.sha256(label.read_bytes()).hexdigest(),videoSHA256=hashlib.sha256(video.read_bytes()).hexdigest()))
(OUTPUT/"pose-quality-reference.json").write_text(json.dumps(dict(set=args.set,samples=samples)))
(ROOT/"artifacts/pose-review").mkdir(parents=True,exist_ok=True)
(ROOT/f"artifacts/pose-review/penn-{args.set}-provenance.json").write_text(json.dumps(provenance,indent=2))
print("Prepared",len(samples),"held-out frames; all media/reference coordinates stay ignored.")
