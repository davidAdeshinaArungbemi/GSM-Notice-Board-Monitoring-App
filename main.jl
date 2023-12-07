using Revise
using GLFW
using CImGui
using CImGui.ImGuiGLFWBackend
using CImGui.ImGuiGLFWBackend.LibCImGui
using CImGui.ImGuiGLFWBackend.LibGLFW
using CImGui.ImGuiOpenGLBackend
using CImGui.ImGuiOpenGLBackend.ModernGL
using DataFrames
using CSV
using CImGui.CSyntax

glfwDefaultWindowHints()
glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2)
if Sys.isapple()
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE) # 3.2+ only
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE) # required on Mac
end

# create window
window = glfwCreateWindow(1280, 720, "SMS Notice Board Monitor", C_NULL, C_NULL)
@assert window != C_NULL
glfwMakeContextCurrent(window)
glfwSwapInterval(1)  # enable vsync

# create OpenGL and GLFW context
window_ctx = ImGuiGLFWBackend.create_context(window)
gl_ctx = ImGuiOpenGLBackend.create_context()

# setup Dear ImGui context
ctx = CImGui.CreateContext()

# enable docking and multi-viewport
io = CImGui.GetIO()
io.ConfigFlags = unsafe_load(io.ConfigFlags) | CImGui.ImGuiConfigFlags_DockingEnable
# io.ConfigFlags = unsafe_load(io.ConfigFlags) | CImGui.ImGuiConfigFlags_ViewportsEnable

# setup Dear ImGui style
CImGui.StyleColorsDark()
# CImGui.StyleColorsClassic()
# CImGui.StyleColorsLight()

# When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
style = Ptr{ImGuiStyle}(CImGui.GetStyle())
if unsafe_load(io.ConfigFlags) & ImGuiConfigFlags_ViewportsEnable == ImGuiConfigFlags_ViewportsEnable
    style.WindowRounding = 5.0f0
    col = CImGui.c_get(style.Colors, CImGui.ImGuiCol_WindowBg)
    CImGui.c_set!(style.Colors, CImGui.ImGuiCol_WindowBg, ImVec4(col.x, col.y, col.z, 1.0f0))
end

# load Fonts
# - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use `CImGui.PushFont/PopFont` to select them.
# - `CImGui.AddFontFromFileTTF` will return the `Ptr{ImFont}` so you can store it if you need to select the font among multiple.
# - If the file cannot be loaded, the function will return C_NULL. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
# - The fonts will be rasterized at a given size (w/ oversampling) and stored into a texture when calling `CImGui.Build()`/`GetTexDataAsXXXX()``, which `ImGui_ImplXXXX_NewFrame` below will call.
# - Read 'fonts/README.txt' for more instructions and details.
fonts_dir = joinpath(@__DIR__, "..", "fonts")
fonts = unsafe_load(CImGui.GetIO().Fonts)
# default_font = CImGui.AddFontDefault(fonts)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Cousine-Regular.ttf"), 15)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "DroidSans.ttf"), 16)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Karla-Regular.ttf"), 10)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "ProggyTiny.ttf"), 10)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Roboto-Medium.ttf"), 16)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Recursive Mono Casual-Regular.ttf"), 16)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Recursive Mono Linear-Regular.ttf"), 16)
# CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Recursive Sans Casual-Regular.ttf"), 16)
CImGui.AddFontFromFileTTF(fonts, "Inter font/Inter-VariableFont_slnt,wght.ttf", 16)

# @assert default_font != C_NULL

# setup Platform/Renderer bindings
ImGuiGLFWBackend.init(window_ctx)
ImGuiOpenGLBackend.init(gl_ctx)

activate_refresh::Bool = false
data::Vector{Vector{String}} = Vector{Vector{String}}([])
selectable_state::Vector{Bool} = Vector{Bool}([])
message_index::UInt = 0

function Refresh() #refresh message
    global data = []
    global selectable_state = []
    global message_index = 0

    df = CSV.File("data.csv") |> DataFrame
    num_rows, num_columns = size(df)

    for i in 1:num_rows
        push!(selectable_state, false)
        push!(data, [string(df[i, 1]), string(df[i, 2]), string(df[i, 3])])
    end
end

function DeleteMessage()
    index_remove = -1
    for counter in eachindex(data) #deselect all
        if selectable_state[counter] == true
            index_remove = counter
            break
        end
    end

    if index_remove == -1
        println("No message selected") #send to logs later
        return
    end

    deleteat!(data, index_remove) #remove vector at index_remove
    deleteat!(selectable_state, index_remove) #remove state at index_remove

    df = DataFrame(data, :auto)
    df = permutedims(df)

    try
        rename!(df, [:Number, :Time, :Message])
        csv_file_path = "data.csv"
        CSV.write(csv_file_path, df)
    catch
        csv_file_path = "data.csv"
        CSV.write(csv_file_path, df)
    end

    Refresh()
end

try
    demo_open = true
    clear_color = Cfloat[0.45, 0.55, 0.60, 1.00]
    while glfwWindowShouldClose(window) == 0
        glfwPollEvents()
        # start the Dear ImGui frame
        ImGuiOpenGLBackend.new_frame(gl_ctx)
        ImGuiGLFWBackend.new_frame(window_ctx)
        CImGui.NewFrame()

        width, height = Ref{Cint}(), Ref{Cint}()
        glfwGetWindowSize(window, width, height)

        # demo_open && @c CImGui.ShowDemoWindow(&demo_open)
        CImGui.SetNextWindowPos((0, 0))
        CImGui.SetNextWindowSize((width[], height[]))

        CImGui.Begin("window", C_NULL, CImGui.ImGuiWindowFlags_NoTitleBar | CImGui.ImGuiWindowFlags_NoMove |
                                       CImGui.ImGuiWindowFlags_NoScrollbar | CImGui.ImGuiWindowFlags_NoResize)

        CImGui.BeginChild("Status", (width[] * 0.989, height[] * 0.037), true, CImGui.ImGuiWindowFlags_NoScrollbar)
        CImGui.TextColored((1.0, 1.0, 0.5, 1.0), "LCD Status: ")
        CImGui.SameLine()
        CImGui.TextColored((0.0, 1.0, 0.0, 1.0), "Good")
        CImGui.SameLine()
        CImGui.TextColored((1.0, 1.0, 0.5, 1.0), "Network Status: ")
        CImGui.SameLine()
        CImGui.TextColored((0.0, 1.0, 0.0, 1.0), "Good")

        CImGui.EndChild()

        CImGui.BeginChild("Main Window", (width[] * 0.989, height[] * 0.941), false)

        CImGui.BeginChild("ReceiverSection", (width[] * 0.2, height[] * 0.941), true)

        CImGui.BeginTabBar("Tabs")

        if CImGui.BeginTabItem("Received")

            CImGui.TextColored((0.0, 1.0, 0.0, 1.0), "Received Messages")
            CImGui.SameLine(0.0, -1)

            CImGui.PushStyleVar(CImGui.ImGuiStyleVar_FrameRounding, 10.0)

            if CImGui.Button("Refresh")
                Refresh()
            end

            CImGui.Separator()

            for row_index in eachindex(data)
                if CImGui.Selectable("Phone Number: $(data[row_index][1])\nTime: $(data[row_index][2])", selectable_state[row_index], 0) #create selectable
                    for counter in eachindex(data) #deselect all
                        global selectable_state[counter] = false
                    end
                    global message_index = row_index
                    global selectable_state[row_index] = true #select selectable

                end
                CImGui.Dummy((0, 5))
            end

            CImGui.PopStyleVar()

            CImGui.EndTabItem()

        end

        if CImGui.BeginTabItem("Allowed")

            CImGui.TextColored((0.0, 1.0, 0.0, 1.0), "Allowed List")
            CImGui.Separator()

            CImGui.EndTabItem()

        end

        CImGui.EndTabBar()

        CImGui.EndChild()

        CImGui.SameLine()

        CImGui.BeginChild("Row layout", (width[] * 0.784, height[] * 0.941), false, CImGui.ImGuiWindowFlags_NoScrollbar)

        CImGui.BeginChild("Message Box", (width[] * 0.784, height[] * 0.47), true)
        CImGui.TextColored((0.0, 1.0, 1.0, 1.0), "Message Box")
        CImGui.Separator()

        if CImGui.Button("Load to LCD1")

        end

        CImGui.SameLine()
        CImGui.Button("Load to LCD2")
        CImGui.SameLine()

        if CImGui.Button("Reject Message")
            DeleteMessage()
        end

        CImGui.Separator()

        # CImGui.SameLine(0.0, -1)
        if message_index != 0
            CImGui.TextWrapped(data[message_index][3])

        else
            CImGui.TextWrapped("")
        end

        CImGui.EndChild()

        CImGui.BeginChild("Logs", (width[] * 0.784, height[] * 0.465), true)
        CImGui.TextColored((1.0, 0.8, 0.0, 1.0), "Logs")
        CImGui.Separator()

        CImGui.TextWrapped("A text")

        CImGui.EndChild()

        CImGui.EndChild()

        CImGui.EndChild()

        CImGui.End()

        # rendering
        CImGui.Render()
        glfwMakeContextCurrent(window)

        width, height = Ref{Cint}(), Ref{Cint}() #! need helper fcn
        glfwGetFramebufferSize(window, width, height)
        display_w = width[]
        display_h = height[]

        glViewport(0, 0, display_w, display_h)
        glClearColor(clear_color...)
        glClear(GL_COLOR_BUFFER_BIT)
        ImGuiOpenGLBackend.render(gl_ctx)

        if unsafe_load(igGetIO().ConfigFlags) & ImGuiConfigFlags_ViewportsEnable == ImGuiConfigFlags_ViewportsEnable
            backup_current_context = glfwGetCurrentContext()
            igUpdatePlatformWindows()
            GC.@preserve gl_ctx igRenderPlatformWindowsDefault(C_NULL, pointer_from_objref(gl_ctx))
            glfwMakeContextCurrent(backup_current_context)
        end

        glfwSwapBuffers(window)
    end
catch e
    @error "Error in renderloop!" exception = e
    Base.show_backtrace(stderr, catch_backtrace())
finally
    ImGuiOpenGLBackend.shutdown(gl_ctx)
    ImGuiGLFWBackend.shutdown(window_ctx)
    CImGui.DestroyContext(ctx)
    glfwDestroyWindow(window)

end

