-- piwip v0.1.0
-- a realtime sampler
--
-- llllllll.co/t/piwip
--
--
--
--    ▼ instructions below ▼
--
-- K2 arms recording
-- K3 forces recording
-- K1+K2 toggles monitor
-- E1 activates presets
-- E2/E3 trims sample

-- state variable
s={
  v={},-- voices to be initialized in init()
  freqs={},-- stores frequency information
  amps={},--store amp information
  update_ui=false,-- toggles redraw
  recording=false,-- recording state
  force_recording=false,
  loop_end=0,-- amount recorded into buffer
  loop_bias={0,0},-- bias the start/end of loop
  silence_time=0,-- amount of silence (during recording)
  armed=false,
  median_frequency=262,
  mode=0,
  mode_name="",
  shift=false,
  monitor=true,
  message="",
}

function init()
  params:add_separator("piwip")
  params:add_taper("resolution","resolution",10,200,50,0,"ms")
  params:set_action("resolution",update_parameters)
  params:add_control("rec thresh","rec thresh",controlspec.new(1,100,'exp',1,20,'amp/1k'))
  params:set_action("rec thresh",update_parameters)
  params:add_taper("silence to stop","silence to stop",10,500,200,0,"ms")
  params:set_action("silence to stop",update_parameters)
  params:add_control("vol pinch","vol pinch",controlspec.new(0,1000,'lin',1,500,'ms'))
  params:set_action("vol pinch",update_parameters)
  params:add_taper("min recorded","min recorded",10,1000,60,0,"ms")
  params:set_action("min recorded",update_parameters)
  params:add_option("notes start at 0","notes start at 0",{"no","yes"},1)
  params:set_action("notes start at 0",update_parameters)
  params:add_option("live follow","live follow",{"no","yes"},2)
  params:set_action("live follow",update_parameters)
  params:add_option("keep armed","keep armed",{"no","yes"},1)
  params:set_action("keep armed",update_parameters)
  params:add_option("playback reference","playback reference",{"middle C","median","realtime"},1)
  params:set_action("playback reference",update_parameters)
  params:add_option("only play during rec","only play during rec",{"no","yes"},1)
  params:set_action("only play during rec",update_parameters)
  params:add_option("midi during rec","midi during rec",{"disabled","enabled"},1)
  params:set_action("midi during rec",update_parameters)
  
  params:read(_path.data..'piwip/'.."piwip.pset")
  
  for i=1,6 do
    s.v[i]={}
    s.v[i].position=0
    s.v[i].last_position=0
    s.v[i].midi=0 -- target midi note
    s.v[i].freq=0 -- current frequency
    s.v[i].ref_freq=0 -- target frequency
    s.v[i].loop_end=0
    s.v[i].started=false
    s.v[i].loop_bias={0,0}
  end
  
  -- initialize timers
  -- initialize timer for updating screen
  timer=metro.init()
  timer.time=params:get("resolution")/1000
  timer.count=-1
  timer.event=update_main
  timer:start()
  
  -- position poll
  softcut.event_phase(update_positions)
  softcut.poll_start_phase()
  
  -- frequency poll (average l+r channels)
  local pitch_poll_l=poll.set("pitch_in_l",function(value)
    update_freq(value)
  end)
  pitch_poll_l.time=params:get("resolution")/1000
  pitch_poll_l:start()
  local pitch_poll_r=poll.set("pitch_in_r",function(value)
    update_freq(value)
  end)
  pitch_poll_r.time=params:get("resolution")/1000
  pitch_poll_r:start()
  
  -- amplitude poll
  p_amp_in=poll.set("amp_in_l")
  p_amp_in.time=params:get("resolution")/1000
  p_amp_in.callback=update_amp
  p_amp_in:start()
  
  -- watch midi
  midi_signal_in=midi.connect(1)
  midi_signal_in.event=update_midi
  
  -- initialize softcut
  for i=1,6 do
    if i==1 then
      -- voice 1 records into buffer, but does not play
      softcut.level(i,0)
      softcut.level_input_cut(1,i,1)
      softcut.level_input_cut(2,i,1)
      softcut.rec_level(i,1)
      softcut.pre_level(i,0)
    else
      softcut.level(i,1)
      softcut.level_input_cut(1,i,0)
      softcut.level_input_cut(2,i,0)
    end
    softcut.pan(i,0)
    softcut.play(i,0)
    softcut.rec(i,0)
    softcut.rate(i,1)
    softcut.loop_start(i,0)
    softcut.loop_end(i,300)
    softcut.loop(i,1)
    
    softcut.fade_time(i,0.2)
    softcut.level_slew_time(i,2)
    softcut.rate_slew_time(i,params:get("resolution")/1000/10)
    
    softcut.buffer(i,1)
    softcut.position(i,0)
    softcut.enable(i,1)
    softcut.phase_quant(i,params:get("resolution")/1000/2)
  end
  
end

--
-- updaters
--
function update_parameters(x)
  params:write(_path.data..'piwip/'.."piwip.pset")
end

function update_positions(i,x)
  -- keep track of bounds of recording
  if i==1 and s.recording then
    s.loop_end=x
  end
  s.v[i].last_position=s.v[i].position
  s.v[i].position=x
  if s.v[i].midi>0 then
    s.update_ui=true
  end
end

function update_freq(f)
  -- ignore frequencies below 30 hz
  if s.recording and f>30 and f<1000 then
    current_position=get_position(1)
    if s.freqs[current_position]~=nil then
      s.freqs[current_position]=(s.freqs[current_position]+f)/2
    else
      s.freqs[current_position]=f
    end
    print("current_position: "..current_position..", f: "..s.freqs[current_position])
    s.median_frequency=median(s.freqs)
  end
end

function get_position(i)
  return tonumber(string.format("%.3f",round_to_nearest(s.v[i].position,params:get("resolution")/1000)))
end

function update_main()
  if s.update_ui then
    redraw()
  end
  if s.monitor_update then
    s.monitor_update=false
    if s.monitor then
      audio.level_monitor(1)
    else
      audio.level_monitor(0)
    end
  end
  -- check active voices and match their pitch using rate
  for i=2,6 do
    -- skip if not playing
    if s.v[i].midi==0 then goto continue end
    
    -- make sure there is a little bit of recorded material
    if s.loop_end<params:get("min recorded")/1000 then goto continue end
    
    -- make sure its bounded by recorded material
    -- and biased by the current bias
    if s.v[i].started==false or s.loop_end~=s.v[i].loop_end or s.v[i].loop_bias[1]~=s.loop_bias[1] or s.v[i].loop_bias[2]~=s.loop_bias[2] then
      -- print("voice "..i.." updating loop points")
      s.v[i].loop_bias={s.loop_bias[1],s.loop_bias[2]}
      s.v[i].loop_end=s.loop_end
      softcut.loop_end(i,s.loop_end-s.loop_bias[2])
      softcut.loop_start(i,s.loop_bias[1])
    end
    
    -- determine target frequency
    local ref_freq=0
    if params:get("playback reference")==2 then
      ref_freq=s.median_frequency
    elseif params:get("playback reference")==3 then
      -- determine from realtime frequencies
      -- modulate the voice's rate to match upcoming pitch
      -- find the closest pitch
      -- values={}
      -- for j=0,1,0.1 do
      --   next_position=s.v[i].position+j*(s.v[i].position-s.v[i].last_position)
      --   index,f=nearest_value(s.freqs,next_position)
      --   table.insert(values,f)
      --   print(f)
      -- end
      -- ref_freq=median(values)
      -- print("next_position: "..next_position)
      -- print("index: "..index)
      -- print("ref_freq: "..ref_freq)
      index,ref_freq=nearest_value(s.freqs,s.v[i].position+params:get("resolution")/1000*2)
    else
      -- middle c
      ref_freq=261.63
    end
    
    -- initialize the voice playing
    if s.v[i].started==false then
      print("starting "..i)
      s.v[i].started=true
      if s.recording and params:get("live follow")==2 then
        s.v[i].position=util.clamp(s.v[1].position-params:get("min recorded")/1000,s.loop_bias[1],s.loop_end-s.loop_bias[2])
      elseif params:get("notes start at 0")==2 then
        s.v[i].position=s.loop_bias[1]
      else
        s.v[i].position=util.clamp(s.v[i].position,s.loop_bias[1],s.loop_end-s.loop_bias[2])
      end
      softcut.position(i,s.v[i].position)
      softcut.play(i,1)
      softcut.level(i,0.5)
    end
    
    -- update the rate to match correctly modulate upcoming pitch
    if s.v[i].ref_freq~=ref_freq and ref_freq~=nil then
      s.v[i].ref_freq=ref_freq
      -- print("ref_freq: "..ref_freq)
      softcut.rate(i,s.v[i].freq/s.v[i].ref_freq)
    end
    ::continue::
  end
end

function rec_start()
  print("init recording")
  -- reset positions of all current notes
  for i=2,6 do
    softcut.position(i,s.loop_bias[1])
    softcut.level(i,0)
    s.v[i].started=false
  end
  -- initialize recording
  softcut.position(1,0)
  softcut.play(1,1)
  softcut.loop_end(1,300)
  s.freqs={}
  s.amps={}
  s.loop_bias={0,0}
  s.recording=true
  s.loop_end=1
  s.silence_time=0
  -- slowly start recording
  -- ease in recording signal to avoid clicks near loop points
  clock.run(function()
    if params:get("vol pinch")>0 then
      for j=1,10 do
        softcut.rec(1,j*0.1)
        clock.sleep(params:get("vol pinch")/10/1000)
      end
    end
    softcut.rec(1,1)
  end)
end

function rec_stop()
  print("stop recording")
  s.recording=false
  -- slowly stop
  clock.run(function()
    if params:get("vol pinch")>0 then
      for j=1,10 do
        softcut.rec(1,(10-j)*0.1)
        clock.sleep(params:get("vol pinch")/10/1000)
      end
    end
    softcut.rec(1,0)
    softcut.play(1,0)
    softcut.position(1,0)
    s.loop_end=s.v[1].position-(params:get("silence to stop")/1000)
  end)
  if params:get("keep armed")==1 then
    s.armed=false
  end
  if params:get("only play during rec")==2 then
    -- shtudown notes
    for i=2,6 do
      if s.v[i].midi>0 then
        print("voice "..i.." off")
        softcut.level(i,0)
        s.v[i].midi=0
        s.v[i].freq=0
        s.v[i].started=false
      end
    end
  end
end

function update_amp(val)
  -- toggle recording on with incoming amplitude
  -- toggle recording off with silence
  if s.recording then
    table.insert(s.amps,val)
    s.update_ui=true
  end
  if val>params:get("rec thresh")/1000 then
    -- reset silence time
    s.silence_time=0
    if not s.recording and s.armed then
      rec_start()
    end
  elseif s.recording and not s.force_recording then
    -- not above threshold, should add to silence time
    -- to eventually trigger stop recording
    s.silence_time=s.silence_time+params:get("resolution")/1000
    if s.silence_time>params:get("silence to stop")/1000 then
      rec_stop()
    end
  end
end

function update_midi(data)
  msg=midi.to_msg(data)
  if msg.type=='note_on' then
    if params:get("only play during rec")==2 and not s.recording then
      do return end

    end
    if params:get("midi during rec")==1 and (s.recording or s.armed) then
      do return end
    end
    -- find first available voice and turn it on
    -- it will be initialized in update_main
    for i=2,6 do
      if s.v[i].midi==0 then
        print("voice "..i.." "..msg.note.." on")
        s.v[i].midi=msg.note
        s.v[i].freq=midi_to_hz(msg.note)
        s.v[i].ref_freq=0
        break
      end
    end
  elseif msg.type=='note_off' then
    -- turn off any voices on that note
    for i=2,6 do
      if s.v[i].midi==msg.note then
        print("voice "..i.." "..msg.note.." off")
        softcut.level(i,0)
        s.v[i].midi=0
        s.v[i].freq=0
        s.v[i].started=false
      end
    end
  end
end

--
-- input
--

function key(n,z)
  if n==1 then
    if z==1 then
      s.shift=true
    else
      s.shift=false
    end
  elseif s.shift and n==2 and z==1 then
    -- toggle monitor
    s.monitor=not s.monitor
    s.monitor_update=true
    if s.monitor then
      show_message("monitor enabled")
    else
      show_message("monitor disabled")
    end
  elseif not s.shift and n==2 and z==1 then
    s.armed=not s.armed
  elseif not s.shift and n==3 and z==1 then
    s.recording=not s.recording
    s.force_recording=s.recording
    if s.recording then
      rec_start()
    else
      rec_stop()
    end
  end
  s.update_ui=true
end

function enc(n,d)
  if n==1 then
    if s.mode==0 then
      params:write(_path.data..'piwip/'.."piwip_temp.pset")
    end
    s.mode=util.clamp(s.mode+sign(d),0,4)
    if s.mode==0 then
      s.mode_name=""
      params:read(_path.data..'piwip/'.."piwip_temp.pset")
    elseif s.mode==1 then
      s.mode_name="sampler"
      params:set("live follow",1)
      params:set("keep armed",1)
      params:set("playback reference",1)
      params:set("only play during rec",1)
      params:set("notes start at 0",2)
      params:set("midi during rec",1)
      s.armed=true
    elseif s.mode==2 then
      s.mode_name="follower"
      params:set("live follow",2)
      params:set("keep armed",2)
      params:set("silence to stop",100)
      params:set("playback reference",3)
      params:set("only play during rec",2)
      params:set("notes start at 0",1)
      params:set("midi during rec",2)
      s.armed=true
    end
  elseif n==2 then
    s.loop_bias[1]=util.clamp(s.loop_bias[1]+d/100,0,s.loop_end-s.loop_bias[2])
  elseif n==3 then
    s.loop_bias[2]=util.clamp(s.loop_bias[2]-d/100,s.loop_bias[1],s.loop_end)
  end
  s.update_ui=true
end
--
-- screen
--
function redraw()
  s.update_ui=false
  screen.clear()
  
  shift=0
  if s.shift then
    shift=5
  end
  
  if s.recording then
    screen.level(15)
    screen.rect(108-shift,1+shift,20,10)
    screen.stroke()
    screen.move(111-shift,8+shift)
    screen.text("REC")
  elseif s.armed then
    screen.level(1)
    screen.rect(108-shift,1+shift,20,10)
    screen.stroke()
    screen.move(111-shift,8+shift)
    screen.text("RDY")
  end
  
  screen.level(15)
  if #s.amps==0 then
    screen.move(64,32-8)
    screen.text_center("play instruments")
    screen.move(64,32)
    screen.text_center("while")
    screen.move(64,32+8)
    screen.text_center("instruments play")
  else
    draw_waveform()
  end
  
  screen.move(3+shift,60-shift)
  screen.level(15)
  screen.text(s.mode_name)
  
  if s.message~="" then
    screen.level(0)
    x=64
    y=28
    w=string.len(s.message)*6
    screen.rect(x-w/2,y,w,10)
    screen.fill()
    screen.level(15)
    screen.rect(x-w/2,y,w,10)
    screen.stroke()
    screen.move(x,y+7)
    screen.text_center(s.message)
  end
  
  screen.update()
end

function draw_waveform()
  -- show amplitudes
  local l=1
  local r=128
  local w=r-l
  local m=32
  local h=32
  
  local amps={}
  -- truncate amps to the the current biased loop
  for k,v in pairs(s.amps) do
    if k*params:get("resolution")/1000>=s.loop_bias[1] and k*params:get("resolution")/1000<=s.loop_end-s.loop_bias[2] then
      table.insert(amps,v)
    end
  end
  maxval=max(amps)
  nval=#amps
  
  maxw=nval
  if maxw>w then
    maxw=w
  end
  
  -- find active positions
  active_pos={}
  for i=2,6 do
    if s.v[i].midi>0 then
      curpos=(s.v[i].position-s.v[i].loop_bias[1])/(s.loop_end-s.v[i].loop_bias[2]-s.v[i].loop_bias[1])
      table.insert(active_pos,round(curpos*maxw))
      table.insert(active_pos,round(curpos*maxw)+1)
      table.insert(active_pos,round(curpos*maxw)-1)
    end
  end
  
  disp={}
  for i=1,w do
    disp[i]=-1
  end
  if nval<w then
    -- draw from left to right
    for k,v in pairs(amps) do
      disp[k]=(v/maxval)*h
    end
  else
    for i=1,w do
      disp[i]=-2
    end
    for k,v in pairs(amps) do
      i=round(w/nval*k)
      if i>=1 and i<=w then
        if disp[i]==-2 then
          disp[i]=(v/maxval)*h
        else
          disp[i]=(disp[i]+(v/maxval)*h)/2
        end
      end
    end
    for k,v in pairs(disp) do
      if v==-2 then
        if k==1 then
          disp[k]=0
        else
          disp[k]=disp[k-1]
        end
      end
    end
  end
  
  maxval=max(disp)
  for k,v in pairs(disp) do
    if v==-1 then
      break
    end
    bright=false
    for l,u in pairs(active_pos) do
      if k==u then
        bright=true
      end
    end
    if bright then
      screen.level(15)
    else
      screen.level(1)
    end
    screen.move(l+k,m)
    screen.line(l+k,m+(v/maxval)*h)
    screen.line(l+k,m-(v/maxval)*h)
    screen.stroke()
  end
end
--
-- utils
--
function round(x)
  return x>=0 and math.floor(x+0.5) or math.ceil(x-0.5)
end

function sign(x)
  if x>0 then
    return 1
  elseif x<0 then
    return-1
  else
    return 0
  end
end

function round_to_nearest(x,yth)
  remainder=x%yth
  if remainder==0 then
    return x
  end
  return x+yth-remainder
end

function midi_to_hz(note)
  return (440/32)*(2^((note-9)/12))
end

function max(a)
  local values={}
  
  for k,v in pairs(a) do
    values[#values+1]=v
  end
  table.sort(values) -- automatically sorts lowest to highest
  
  return values[#values]
end

-- Get the median of a table.
-- http://lua-users.org/wiki/SimpleStats
function median(t)
  local temp={}
  
  -- deep copy table so that when we sort it, the original is unchanged
  -- also weed out any non numbers
  for k,v in pairs(t) do
    if type(v)=='number' then
      table.insert(temp,v)
    end
  end
  
  table.sort(temp)
  
  -- If we have an even number of table elements or odd.
  if math.fmod(#temp,2)==0 then
    -- return mean value of middle two elements
    return (temp[#temp/2]+temp[(#temp/2)+1])/2
  else
    -- return middle element
    return temp[math.ceil(#temp/2)]
  end
end

function show_message(message)
  clock.run(function()
    s.message=message
    redraw()
    clock.sleep(0.5)
    s.message=""
    redraw()
  end)
end

function nearest_value(t,number)
  local best_diff=10000
  local closet_index=1
  for i,y in pairs(t) do
    local d=math.abs(number-i)
    if d<best_diff then
      best_diff=d
      closet_index=i
    end
  end
  return closet_index,t[closet_index]
end

function quantile(t,q)
  assert(t~=nil,"No table provided to quantile")
  assert(q>=0 and q<=1,"Quantile must be between 0 and 1")
  table.sort(t)
  local position=#t*q+0.5
  local mod=position%1
  
  if position<1 then
    return t[1]
  elseif position>#t then
    return t[#t]
  elseif mod==0 then
    return t[position]
  else
    return mod*t[math.ceil(position)]+
    (1-mod)*t[math.floor(position)]
  end
end
