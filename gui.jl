using Revise
include("Renderer.jl")
using CImGui
using GLFW
import Base: C_NULL

showCloseIcon = true
showCloseIconPtr = Ref(showCloseIcon)


Renderer.render(width=800, height=500, title="Notice Board Monitor") do
    CImGui.Begin("Sender")
    CImGui.Button("My Button") && @show "triggered"
    CImGui.End()

    CImGui.Begin("Messages")
    # CImGui.Button("My Button") && @show "triggered"
    CImGui.End()
end