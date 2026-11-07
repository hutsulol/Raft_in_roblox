while true do
	wait(5)
	script.Parent.AmmoLeft.Value = script.Parent.AmmoLeft.Value +5
	script.Parent.Parent.Interface.Frame.Barra.Amount.Text = script.Parent.AmmoLeft.Value .." / "..script.Parent.AmmoLeft.MaxValue
	script.Parent.Parent.Interface.Frame.Barra.Valor.Size = UDim2.new(script.Parent.AmmoLeft.Value/script.Parent.AmmoLeft.MaxValue,0,1,0)
	script.Parent.Parent.GUI.Frame.Amount.Text = script.Parent.AmmoLeft.Value .." / "..script.Parent.AmmoLeft.MaxValue
end