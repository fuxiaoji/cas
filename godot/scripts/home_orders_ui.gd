extends RefCounted
## Existing facilities receive a small, explicit prepaid order menu.
const Design=preload("res://scripts/ui_design.gd")
static func _amounts(home_value:Dictionary,wallet_value:Dictionary)->String:
	var parts:PackedStringArray=[]
	var names:Dictionary={"scrap":"浮材","alloy":"合金","energy":"能源","protocols":"协议片","credits":"岛屿补给"}
	for key in home_value:parts.append("%s %d"%[str(names.get(key,key)),int(home_value[key])])
	var materials:Dictionary={"credits":"银币","materials":"基础航海记录","training_t2":"战术训练记录","training_t3":"精英训练记录","core_t1":"基础突破核心","core_t2":"精制突破核心","core_t3":"完整突破核心"}
	for key in wallet_value:parts.append("%s %d"%[str(materials.get(key,key)),int(wallet_value[key])])
	return " · ".join(parts) if not parts.is_empty() else "无"

static func _confirm_cancel(owner,facility_id:String,quote_changed:bool=false)->void:
	# Re-quote when the player clicks; an open sheet may be several minutes old.
	var processing=owner.service.processing()
	var quote:Dictionary=processing.cancel_preview(facility_id)
	if not quote.get("ok",false) or not quote.get("ready",false):
		owner.app.notify({"ok":false,"message":"订单状态已变化，请查看当前产物。"})
		open(owner,facility_id)
		return
	var prefix:String="订单进度已变化，请重新确认当前退款。\n" if quote_changed else ""
	var explanation:String=prefix+"退还："+_amounts(quote.home_refund,quote.wallet_refund)+"。已开工的当前批次会消耗原料，完成的产物仍可领取。"
	owner.app.confirm_action(explanation,func():
		# The transactional guard also covers crossing a batch boundary immediately
		# after confirmation. Changed refunds return without any account mutation.
		var result:Dictionary=processing.cancel(facility_id,"order-cancel-%d"%Time.get_ticks_usec(),-1,quote)
		if bool(result.get("quote_changed",false)):
			_confirm_cancel(owner,facility_id,true)
			return
		owner.app.notify(result);owner.refresh();open(owner,facility_id))

static func open(owner,facility_id:String)->void:
	var processing=owner.service.processing()
	if not processing.enabled():return
	var state:Dictionary=processing.overview()
	var job:Dictionary={}
	for row in state.jobs:
		if str(row.facility_id)==facility_id:job=row;break
	var recipe:Dictionary={}
	for row in state.recipes:
		if str(row.facility_id)==facility_id:recipe=row;break
	if recipe.is_empty() and job.is_empty():return
	var layer:Control=owner._home_modal("加工订单")
	var margin:=MarginContainer.new();layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.anchor_left=.245;margin.anchor_top=.265;margin.anchor_right=.755;margin.anchor_bottom=.795
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",16);scroll.add_child(box)
	if not job.is_empty():
		owner._label(box,str(job.name),28)
		var completed_label:Label=owner._label(box,"",21)
		var bar:=ProgressBar.new();bar.custom_minimum_size.y=18;bar.show_percentage=false;bar.max_value=maxi(1,int(job.batches)*int(job.seconds));bar.value=int(job.work_seconds);box.add_child(bar)
		var remaining_label:Label=owner._label(box,"",21)
		var output_label:Label=owner._label(box,"",22)
		var claim_button:Button=owner._button(box,"收取产物",func():
			var result:Dictionary=processing.claim(facility_id,"order-claim-%d"%Time.get_ticks_usec())
			owner.app.notify(result);owner.refresh();open(owner,facility_id),true)
		var update_progress:Callable=func():
			for current in processing.overview().jobs:
				if str(current.facility_id)!=facility_id:continue
				completed_label.text="%d / %d 批完成"%[int(current.completed_batches),int(current.batches)]
				bar.value=int(current.work_seconds)
				remaining_label.text=str(current.pause_reason) if bool(current.paused) else "剩余 %d 分钟"%ceili(float(current.remaining_seconds)/60.0)
				output_label.text="待领取："+_amounts(current.claimable_home,current.claimable_wallet)
				claim_button.disabled=int(current.claimable_batches)<=0
				return
		var timer:=Timer.new();timer.wait_time=1.0;box.add_child(timer);timer.timeout.connect(update_progress);timer.start();update_progress.call()
		var cancel:Dictionary=processing.cancel_preview(facility_id)
		if cancel.get("ok",false) and cancel.get("ready",false):
			owner._button(box,"取消未完成订单",func():_confirm_cancel(owner,facility_id))
		return
	owner._label(box,str(recipe.name),28)
	owner._label(box,str(recipe.description),21)
	var quantity:=Label.new();quantity.add_theme_font_size_override("font_size",23);box.add_child(quantity)
	var slider:=HSlider.new();slider.name="OrderBatchSlider";slider.min_value=1;slider.max_value=maxi(1,int(recipe.max_batches));slider.step=1;slider.value=1;slider.custom_minimum_size.y=54;box.add_child(slider)
	var summary:=Label.new();summary.name="OrderQuote";summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;summary.add_theme_font_size_override("font_size",22);box.add_child(summary)
	var confirm:=Button.new();confirm.name="StartProcessingOrder";confirm.custom_minimum_size.y=76;Design.apply_button(confirm,true);box.add_child(confirm)
	var refresh:Callable=func():
		var quote:Dictionary=processing.preview(facility_id,str(recipe.id),int(slider.value))
		quantity.text="%d 批 · %d 分钟"%[int(slider.value),ceili(float(quote.get("total_seconds",0))/60.0)]
		summary.text="投入："+_amounts(quote.get("home_cost",{}),quote.get("wallet_cost",{}))+"\n获得："+_amounts(quote.get("home_output",{}),quote.get("wallet_output",{}))
		confirm.disabled=not bool(quote.get("ready",false));confirm.text="开始加工" if not confirm.disabled else str(quote.get("message","条件不足"))
		confirm.set_meta("quote",quote)
	slider.value_changed.connect(func(_value:float):refresh.call())
	confirm.pressed.connect(func():
		var quote:Dictionary=confirm.get_meta("quote",{})
		var result:Dictionary=processing.start(facility_id,str(recipe.id),int(slider.value),"order-start-%d"%Time.get_ticks_usec(),{"home":quote.get("home_cost",{}),"wallet":quote.get("wallet_cost",{})})
		owner.app.notify(result);owner.refresh();open(owner,facility_id))
	refresh.call()
