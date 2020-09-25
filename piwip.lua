-- piwip v0.1.0
-- ?
--
-- llllllll.co/t/?
--
--
--
--    ▼ instructions below ▼
--
-- ?

-- state variable
s={
  v={},-- voices to be initialized in init()
  freqs={},-- stores frequency information
  amps={},--store amp information
  update_ui=false,-- toggles redraw
  recording=false,-- recording state
  loop_end=0,-- amount recorded into buffer
  loop_bias={0,0},-- bias the start/end of loop
  silence_time=0,-- amount of silence (during recording)
  armed=true,
}

function init()
  params:add_separator("piwip")
  params:add_taper("slew rate","slew rate",0,30,(60/clock.get_tempo()),0,"s")
  params:set_action("slew rate",update_parameters)
  params:add_taper("resolution","resolution",10,200,50,0,"ms")
  params:set_action("resolution",update_parameters)
  params:add_control("rec thresh","rec thresh",controlspec.new(1,100,'exp',1,20,'amp/1k'))
  params:set_action("rec thresh",update_parameters)
  params:add_taper("debounce time","debounce time",10,500,200,0,"ms")
  params:set_action("debounce time",update_parameters)
  params:add_taper("min recorded","min recorded",10,1000,60,0,"ms")
  params:set_action("min recorded",update_parameters)
  params:add_option("notes reset sample","notes reset sample",{"no","yes"},1)
  params:set_action("notes reset sample",update_parameters)
  
  params:read(_path.data..'piwip/'.."piwip.pset")
  
  for i=1,6 do
    s.v[i]={}
    s.v[i].position=0
    s.v[i].midi=0 -- target midi note
    s.v[i].freq=0 -- current frequency
    s.v[i].loop_end=0
    s.v[i].started=false
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
  pitch_poll_l:start()
  local pitch_poll_r=poll.set("pitch_in_r",function(value)
    update_freq(value)
  end)
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
    softcut.level_slew_time(i,params:get("resolution")/1000*10)
    softcut.rate_slew_time(i,params:get("resolution")/1000*0.25)
    
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
      print(current_position,f)
    end
  end
end

function get_position(i)
  return tonumber(string.format("%.3f",round_to_nearest(s.v[i].position,params:get("resolution")/1000)))
end

function update_main()
  if s.update_ui then
    redraw()
  end
  -- check active voices and match their pitch using rate
  for i=2,6 do
    -- skip if not playing
    if s.v[i].midi==0 then goto continue end
    
    -- make sure there is a little bit of recorded material
    if s.loop_end<params:get("min recorded")/1000 then goto continue end
    
    -- make sure its bounded by recorded material
    if s.loop_end~=s.v[i].loop_end then
      softcut.loop_end(i,s.loop_end)
    end
    
    -- modulate the voice's rate to match upcoming pitch
    -- find the closest pitch
    next_position=nil
    for j=3,0,-1 do
      next_position=get_position(i)+j*params:get("resolution")/1000
      if s.freqs[next_position]~=nil then
        break
      end
    end
    
    -- initialize the voice playing
    if s.v[i].started==false then
      print("starting "..i)
      s.v[i].started=true
      if s.recording then
        s.v[i].position=util.clamp(s.v[1].position-params:get("min recorded")/1000,0,s.loop_end)
      elseif params:get("notes reset sample")==2 then
        s.v[i].position=0
      else
        s.v[i].position=util.clamp(s.v[i].position,0,s.loop_end)
      end
      softcut.position(i,s.v[i].position)
      softcut.play(i,1)
      softcut.level(i,1)
      if next_position~=nil and s.freqs[next_position]~=nil then
        target_freq=s.freqs[next_position]
      elseif #s.freqs>0 then
        target_freq=median(s.freqs)
      else
        target_freq=s.v[i].freq
      end
      if target_freq==nil then
        target_freq=s.v[i].freq
      end
      print("target_freq: "..target_freq)
      softcut.rate(i,s.v[i].freq/target_freq)
    end
    
    -- update the rate to match correctly modulate upcoming pitch
    if next_position~=nil and s.freqs[next_position]~=nil then
      softcut.rate(i,s.v[i].freq/s.freqs[next_position])
    end
    ::continue::
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
      print("init recording")
      softcut.position(1,0)
      softcut.rec(1,1)
      softcut.play(1,1)
      softcut.loop_end(1,300)
      s.freqs={}
      s.amps={}
      s.recording=true
      s.loop_end=1
      -- reset positions of all current notes
      for i=2,6 do
        softcut.position(i,0)
        softcut.level(i,0)
        s.v[i].started=false
      end
    end
  elseif s.recording then
    -- not above threshold, should add to silence time
    -- to eventually trigger stop recording
    s.silence_time=s.silence_time+params:get("resolution")/1000
    if s.silence_time>params:get("debounce time")/1000 then
      print("stop recording")
      s.recording=false
      softcut.rec(1,0)
      softcut.play(1,0)
      softcut.position(1,0)
      s.loop_end=s.v[1].position-(params:get("debounce time")/1000)
    end
  end
end

function update_midi(data)
  msg=midi.to_msg(data)
  if msg.type=='note_on' then
    -- find first available voice and turn it on
    -- it will be initialized in update_main
    for i=2,6 do
      if s.v[i].midi==0 then
        print("voice "..i.." "..msg.note.." on")
        s.v[i].midi=msg.note
        s.v[i].freq=midi_to_hz(msg.note)
        break
      end
    end
  elseif msg.type=='note_off' then
    -- turn off any voices on that note
    for i=2,6 do
      if s.v[i].midi==msg.note then
        print("voice "..i.." "..msg.note.." off")
        softcut.level(i,0)
        softcut.play(i,0)
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
  if z==1 then
    s.armed=not s.armed
    print(s.armed)
    s.update_ui=true
  end
end
--
-- screen
--
function redraw()
  s.update_ui=false
  screen.clear()
  
  if s.recording then
    screen.level(15)
    screen.rect(108,1,20,10)
    screen.stroke()
    screen.move(111,8)
    screen.text("REC")
  elseif s.armed then
    screen.level(1)
    screen.rect(108,1,20,10)
    screen.stroke()
    screen.move(111,8)
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
  screen.update()
end

function draw_waveform()
  -- show amplitudes
  local l=1
  local r=128
  local w=r-l
  local m=32
  local h=32
  maxval=max(s.amps)
  nval=#s.amps
  
  maxw=nval
  if maxw>w then
    maxw=w
  end
  
  -- find active positions
  active_pos={}
  for i=2,6 do
    if s.v[i].midi>0 then
      table.insert(active_pos,round(s.v[i].position/s.loop_end*maxw))
      table.insert(active_pos,round(s.v[i].position/s.loop_end*maxw)+1)
      table.insert(active_pos,round(s.v[i].position/s.loop_end*maxw)-1)
    end
  end
  
  disp={}
  for i=1,w do
    disp[i]=-1
  end
  if nval<w then
    -- draw from left to right
    for k,v in pairs(s.amps) do
      disp[k]=(v/maxval)*h
    end
  else
    for i=1,w do
      disp[i]=-2
    end
    for k,v in pairs(s.amps) do
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
