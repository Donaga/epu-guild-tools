-- A small map-canvas fixture for exercising the shipped mapping library.
WOW_PROJECT_ID=160; WOW_PROJECT_CAMELOT=160
Enum.UIMapType={Cosmic=0,World=1,Continent=2,Zone=3,Dungeon=4,Micro=5}
function CreateVector2D(x,y) return {GetXY=function() return x,y end} end
function securecallfunction(fn,...) return fn(...) end
function IsLoggedIn() return false end
function UnitPosition() return -500,-400,0,0 end
function GetPlayerFacing() return __facing or 0 end
function GetCVar(k) return (__rotate and k=='rotateMinimap') and '1' or '0' end
function Minimap:GetZoom() return __zoom or 0 end
function Minimap:SetZoom(z) __zoom=z end
function Minimap:GetScale() return 1 end
function Minimap:GetWidth() return 200 end
function Minimap:GetHeight() return 200 end
Minimap:Show()
C_Map={}
function C_Map.GetMapInfo(id)
  if id==42 then return {mapID=id,name='Elwynn',mapType=3,parentMapID=13}
  elseif id==13 then return {mapID=id,name='Eastern Kingdoms',mapType=2,parentMapID=947}
  elseif id==947 then return {mapID=id,name='Azeroth',mapType=1,parentMapID=0} end
end
function C_Map.GetMapChildrenInfo(id)
  if id==947 then return {C_Map.GetMapInfo(13)} elseif id==13 then return {C_Map.GetMapInfo(42)} end
  return {}
end
function C_Map.GetWorldPosFromMapPos(id,p) local x,y=p:GetXY(); return 0,CreateVector2D(-y*1000,-x*1000) end
function C_Map.GetMapWorldSize() return 1000,1000 end
function C_Map.GetBestMapForUnit() return 42 end
function C_Map.GetPlayerMapPosition() return CreateVector2D(0.4,0.5) end
function Mixin(t,...)
  for i=1,select('#',...) do for k,v in pairs(select(i,...)) do t[k]=v end end
  return t
end
function CreateFromMixins(...) return Mixin({},...) end
function CreateFramePool() return {} end
MapCanvasDataProviderMixin={GetMap=function(self) return self.map end}
MapCanvasPinMixin={}
WorldMapFrame=NewMock(); WorldMapFrame.pinPools={}; WorldMapFrame.pins={}
function WorldMapFrame:GetCanvas() return self end
function WorldMapFrame:GetMapID() return __viewMap or 42 end
function WorldMapFrame:AddDataProvider(p) p.map=self; self.provider=p end
function WorldMapFrame:AcquirePin(template,icon,x,y)
  self.pins[icon]={x=x,y=y}; icon:Show()
end
function WorldMapFrame:RemoveAllPinsByTemplate() self.pins={} end
function WorldMapFrame:EnumeratePinsByTemplate()
  local key
  return function() key=next(self.pins,key); if key then return {icon=key} end end
end
function WorldMapFrame:RemovePin(p) self.pins[p.icon]=nil; p.icon:Hide() end
function C_Map.GetMapGroupID() end
