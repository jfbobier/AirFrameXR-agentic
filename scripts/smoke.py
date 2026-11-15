import torch, sys
print("torch", torch.__version__, "cuda", torch.version.cuda, "dev", torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0))
a = torch.ones(1024, 1024, device="cuda"); print("matmul", (a @ a).sum().item())
import vllm; print("vllm", vllm.__version__)
from vllm import _custom_ops as ops
print("cutlass fp8 sm120   :", ops.cutlass_scaled_mm_supports_fp8(120))
print("cutlass block fp8   :", ops.cutlass_scaled_mm_supports_block_fp8(120))
try: print("nvfp4 supported     :", ops.cutlass_scaled_mm_supports_fp4(120))
except Exception as e: print("nvfp4 check err", repr(e)[:200])
import vllm._C_stable_libtorch as c; print("native module:", c.__file__)
x = torch.randn(256, 512, device="cuda", dtype=torch.bfloat16)
try:
    from vllm._custom_ops import scaled_fp4_quant
    gs = torch.tensor(1.0, device="cuda", dtype=torch.float32)
    q, sf = scaled_fp4_quant(x, gs); torch.cuda.synchronize(); print("scaled_fp4_quant OK", tuple(q.shape), tuple(sf.shape))
except Exception as e: print("fp4 quant FAIL", repr(e)[:300])
try:
    w = torch.randn(512, 512, device="cuda", dtype=torch.bfloat16).to(torch.float8_e4m3fn)
    xa = torch.randn(64, 512, device="cuda", dtype=torch.bfloat16).to(torch.float8_e4m3fn)
    sa = torch.ones(1, device="cuda"); sb = torch.ones(1, device="cuda")
    o = ops.cutlass_scaled_mm(xa, w.t(), sa, sb, torch.bfloat16); torch.cuda.synchronize(); print("cutlass_scaled_mm fp8 OK", tuple(o.shape), float(o.float().abs().mean()))
except Exception as e: print("cutlass fp8 FAIL", repr(e)[:300])
