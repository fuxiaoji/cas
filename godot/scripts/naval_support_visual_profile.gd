extends RefCounted
## Presentation only. Blast boundaries always use the published metre radius.
static func for_caliber(caliber_mm:float)->Dictionary:
	if caliber_mm<=139:
		return {"tier":"light","shell_px":1.2,"core_px":.9,"glow_px":2.8,"flash_s":.07,"life_s":.7,"burst_min_px":5.0,"burst_max_px":25.0,"shake":.20,"ring_px":.9}
	if caliber_mm<=219:
		return {"tier":"medium","shell_px":1.8,"core_px":1.3,"glow_px":4.5,"flash_s":.10,"life_s":1.0,"burst_min_px":7.0,"burst_max_px":54.0,"shake":.40,"ring_px":1.2}
	if caliber_mm<350:
		return {"tier":"heavy","shell_px":2.5,"core_px":1.8,"glow_px":7.0,"flash_s":.13,"life_s":1.4,"burst_min_px":10.0,"burst_max_px":100.0,"shake":.67,"ring_px":1.8}
	return {"tier":"capital","shell_px":3.6,"core_px":2.5,"glow_px":11.0,"flash_s":.17,"life_s":1.8,"burst_min_px":14.0,"burst_max_px":180.0,"shake":1.0,"ring_px":2.6}
