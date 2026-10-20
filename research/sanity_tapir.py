"""Known image translations validate point coordinate order/scaling on MPS."""
import json
import os
from pathlib import Path
import sys
os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK','1')
import cv2
import numpy as np
import torch
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT/'vendor'))
from tapnet.torch import tapir_model

torch.set_num_threads(4)
device='mps' if torch.backends.mps.is_available() else 'cpu'
image=cv2.cvtColor(cv2.resize(cv2.imread(str(ROOT/'results/frames/0000.jpg')),(256,256)),cv2.COLOR_BGR2RGB)
frames=np.stack([cv2.warpAffine(image,np.float32([[1,0,2*i],[0,1,i]]),(256,256)) for i in range(8)])
points=np.float32([[771/1280*256,27/720*256],[1035/1280*256,169/720*256]])
queries=np.stack([np.array([0,p[1],p[0]],np.float32) for p in points])
model=tapir_model.TAPIR(pyramid_level=1)
model.load_state_dict(torch.load(ROOT/'models/bootstapir_checkpoint_v2.pt',map_location='cpu',weights_only=True))
model=model.to(device).eval()
with torch.inference_mode():
 result=model(torch.from_numpy(frames).float().to(device)[None]/255*2-1,torch.from_numpy(queries).to(device)[None])
observed=result['tracks'][0].cpu().numpy()
expected=points[:,None,:]+np.array([[2*i,i] for i in range(8)])[None]
error=np.linalg.norm(observed-expected,axis=-1)
data={'device':device,'input':[256,256],'translationPerFrame':[2,1],
 'meanErrorPx':float(error.mean()),'maxErrorPx':float(error.max()),
 'expected':expected.tolist(),'observed':observed.tolist(),
 'purpose':'Validate tyx query coordinate order and xy output scaling, not baseball tracking accuracy.'}
(ROOT/'results/tapir_coordinate_sanity.json').write_text(json.dumps(data,indent=2))
print(json.dumps({k:data[k] for k in ['device','meanErrorPx','maxErrorPx']}),flush=True)
assert error.mean()<5 and error.max()<8,'Known-translation sanity check failed'
