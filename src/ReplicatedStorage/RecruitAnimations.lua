-- R6 poses relative to the imported rig's original Motor6D frames.
local A={}
A.Names={"Дружелюбный","Энергичный","Скромный","Гордый","Танцор","Удивлённый"}
A.Duration={2.8,2.25,3.5,3.0,3.3,3.7}
local function smooth(x) x=math.clamp(x,0,1);return x*x*(3-2*x) end
function A.Travel(v,u)
    local e=smooth(u);local envelope=math.sin(math.pi*u)^2
    local side=({.09,.12,.08,.04,.28,.10})[v]*math.sin(u*math.pi*4)*envelope
    local hop=v==2 and math.abs(math.sin(u*math.pi*5))*.22*envelope or 0
    local yaw=v==5 and math.sin(u*math.pi*6)*.16*envelope or side*.25
    return e,side,hop,yaw
end
-- Shared 30-second work choreography. Mirrored routes stay outside the
-- altar's 2.6-stud base and never cross the central emergence corridor.
function A.WorkerFrame(role,t)
    local side=role==1 and -1 or 1
    local function pose(x,z,tx,tz)
        local p=Vector3.new(x*side,2.4,z)
        return CFrame.lookAt(p,Vector3.new(tx*side,2.4,tz))
    end
    local work=pose(3.6,1.3,0,2.55)
    local station=pose(4.35,2.7,6,2.7)
    local book=pose(4.35,3.5,6,3.55)
    local corner=pose(3.9,-.9,1.65,-2.6)
    local meet=pose(1.65,-2.6,-1.65,-2.6)
    local keys={
        {0,work,"Channel"},{4,work,"Walk"},{6,station,"Prepare"},
        {12,station,"Walk"},{13,book,"Study"},{17,book,"Walk"},
        {19,work,"Channel"},{24,work,"Walk"},{26,corner,"Walk"},
        {28,meet,"Discuss"},{32,meet,"Walk"},{34,corner,"Walk"},{36,work,"Channel"},{40,work,"Channel"}}
    local cycle=t%40
    for i=1,#keys-1 do
        local a,b=keys[i],keys[i+1]
        if cycle>=a[1] and cycle<b[1] then
            local action=a[3]
            if action=="Hammer" and role==2 then action="Read" end
            if action=="Read" and role==1 then action="Channel" end
            local cf=a[2]
            if action=="Walk" then
                local u=smooth((cycle-a[1])/(b[1]-a[1]))
                local position=a[2].Position:Lerp(b[2].Position,u)
                local heading=CFrame.lookAt(position,position+(b[2].Position-a[2].Position))
                local turnIn=smooth((cycle-a[1])/.35)
                local turnOut=smooth((b[1]-cycle)/.35)
                local rotation=a[2].Rotation:Lerp(heading.Rotation,turnIn):Lerp(b[2].Rotation,1-turnOut)
                cf=CFrame.new(position)*rotation
            end
            return cf,action,cycle-a[1]
        end
    end
    return work,"Channel",0
end
function A.Pose(role,v,mode,t,working)
    local p={};local function put(n,x,y,z)
        -- Pose axes are torso-local, independent of imported joint rotations.
        if n:find("Shoulder") then
            local side=n=="Right Shoulder" and 1 or -1
            p[n]=CFrame.Angles(-(z or 0)*side,y or 0,x or 0)
        elseif n:find("Hip") then
            p[n]=CFrame.Angles((z or 0)*(n=="Right Hip" and 1 or -1),y or 0,x or 0)
        else p[n]=CFrame.Angles(x or 0,y or 0,z or 0) end
    end
    local function body(y,lean,turn,roll) p.RootJoint=CFrame.new(0,y,0)*CFrame.Angles(lean or 0,turn or 0,roll or 0) end
    if role>0 then
        local _,action,phase=A.WorkerFrame(role,t)
        local swing=math.sin(phase*9)
        if mode=="Yield" then
            put("Right Shoulder",-.12,0,-.35);put("Left Shoulder",.12,0,.35)
            put("Neck",-.06,math.sin(t)*.12,0)
        elseif action=="Walk" then
            put("Right Hip",0,0,swing*.38);put("Left Hip",0,0,swing*.38)
            put("Right Shoulder",0,0,-swing*.28);put("Left Shoulder",0,0,-swing*.28)
            body(math.abs(swing)*.035,.04,0,swing*.035)
        elseif action=="Prepare" then
            body(-.035,.10,0,.025*math.sin(phase*4));put("Neck",.2,0,0)
        elseif action=="Study" then
            body(0,.09,0,0);put("Neck",.25,.05*math.sin(phase*2),0)
        elseif action=="Hammer" then
            local q=(phase%1.2)/1.2
            local lift=q<.6 and smooth(q/.6) or 1-smooth((q-.6)/.15)
            put("Right Shoulder",-.08,0,-.55-lift*.85)
            put("Left Shoulder",.13,0,.7);body(-.045*(1-lift),.08,0,0)
            put("Neck",.16,0,0)
        elseif action=="Read" then
            put("Left Shoulder",.12,-.12,1.0);put("Right Shoulder",-.18,.1,-.7-.14*math.sin(phase*3))
            put("Neck",.23,math.sin(phase)*.1,0)
        elseif action=="Channel" then
            put("Right Shoulder",-.20,.12,-.9-.13*math.sin(phase*3))
            put("Left Shoulder",.20,-.12,.9+.13*math.sin(phase*3+.5))
            body(.025*math.sin(phase*3),.07,0,.025*math.sin(phase*2));put("Neck",.12,0,0)
        elseif action=="Discuss" then
            local talking=(phase%4<2)==(role==1)
            put("Left Shoulder",.12,0,.7)
            put("Right Shoulder",-.15,0,talking and (-.8-.2*math.sin(phase*5)) or -.35)
            put("Neck",talking and -.06 or .10*math.sin(phase*5),0,.025*math.sin(phase*3))
        else
            put("Right Shoulder",0,0,-.3);put("Left Shoulder",0,0,.35)
            put("Neck",.08*math.sin(phase*2),.12*math.sin(phase),0)
        end
        return p
    end
    if mode=="Walk" then
        local f=({9,13,7,8,10,6.5})[v];local amp=({.43,.62,.26,.48,.48,.3})[v]
        local s=math.sin(t*f)*amp
        put("Right Hip",0,0,s);put("Left Hip",0,0,s)
        put("Right Shoulder",0,0,-s*.8);put("Left Shoulder",0,0,-s*.8)
        body(math.abs(math.sin(t*f))*.045,0,0,math.sin(t*f)*.035)
        if v==1 then put("Right Shoulder",0,0,-1.65+math.sin(t*12)*.18)
        elseif v==2 then body(math.abs(math.sin(t*f))*.10,.08,0,0)
        elseif v==3 then put("Neck",.18,.15*math.sin(t*2),-.08);put("Left Shoulder",0,0,.48)
        elseif v==4 then put("Neck",-.13,0,0);body(.02,-.06,0,math.sin(t*8)*.06)
        elseif v==5 then body(.04,0,math.sin(t*5)*.15,math.sin(t*5)*.12)
        else put("Neck",-.06,math.sin(t*3)*.38,0);put("Right Shoulder",0,0,-.6);put("Left Shoulder",0,0,.6) end
    elseif mode=="Celebrate" then
        local e=math.sin(math.min(t/2.7,1)*math.pi)^2
        if v==1 then -- broad wave
            put("Right Shoulder",0,0,-2.1+math.sin(t*13)*.25);put("Neck",-.08,0,.12)
        elseif v==2 then -- both fists up and happy bounce
            put("Right Shoulder",0,0,-2.3);put("Left Shoulder",0,0,2.3);body(math.abs(math.sin(t*8))*.24,0,0,0)
        elseif v==3 then -- grateful bow, hand to heart
            put("Right Shoulder",-.5,.4,-.8);put("Neck",e*.3,0,0);body(0,e*.28,0,0)
        elseif v==4 then -- proud salute
            put("Right Shoulder",-.3,0,-2.1);put("Left Shoulder",0,0,.45);put("Neck",-.15,0,0)
        elseif v==5 then -- victory dance
            put("Right Shoulder",0,0,-1.5+math.sin(t*8)*.5);put("Left Shoulder",0,0,1.5+math.sin(t*8)*.5)
            put("Right Hip",0,0,math.sin(t*8)*.25);put("Left Hip",0,0,math.sin(t*8)*.25)
            body(math.abs(math.sin(t*8))*.1,0,math.sin(t*5)*.3,math.sin(t*8)*.12)
        else -- surprised hands at cheeks, then open arms
            local spread=smooth((t-.7)/.8)
            put("Right Shoulder",-.3*(1-spread),0,-2.0+spread*.9)
            put("Left Shoulder",.3*(1-spread),0,2.0-spread*.9);put("Neck",-.18,math.sin(t*3)*.1,0)
        end
    elseif mode=="Appear" then body(-.12*(1-smooth(t/.6)),.07,0,0);put("Neck",-.1,0,0) end
    return p
end
return A
