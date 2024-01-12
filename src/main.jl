import Pkg
Pkg.instantiate()
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
using LibSerialPort
using Match

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

# When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
style = Ptr{ImGuiStyle}(CImGui.GetStyle())
if unsafe_load(io.ConfigFlags) & ImGuiConfigFlags_ViewportsEnable == ImGuiConfigFlags_ViewportsEnable
    style.WindowRounding = 5.0f0
    col = CImGui.c_get(style.Colors, CImGui.ImGuiCol_WindowBg)
    CImGui.c_set!(style.Colors, CImGui.ImGuiCol_WindowBg, ImVec4(col.x, col.y, col.z, 1.0f0))
end

fonts_dir = joinpath(@__DIR__, "..", "fonts")
fonts = unsafe_load(CImGui.GetIO().Fonts)
# default_font = CImGui.AddFontDefault(fonts)
CImGui.AddFontFromFileTTF(fonts, "Inter font/Inter-VariableFont_slnt,wght.ttf", 16)

# setup Platform/Renderer bindings
ImGuiGLFWBackend.init(window_ctx)
ImGuiOpenGLBackend.init(gl_ctx)

activate_refresh::Bool = false
data::Vector{Vector{String}} = Vector{Vector{String}}([])
selectable_state::Vector{Bool} = Vector{Bool}([])
message_index::UInt = 0
logs::Vector{String} = []

gsm_output::String = ""
lcd_status::String = "Disconnected"
network_status::String = "No Network"

# for serial communication
portname::String = if Sys.iswindows()
    "COM5"
elseif Sys.isapple()
    "/dev/cu.usbserial-1410"
else
    error("Unknown OS detected!\nSupported OS include: Windows and macOS")
end

global baudrate = 115200 #can change

function Refresh() #refresh message
    global data = []
    global selectable_state = []
    global message_index = 0

    df = CSV.File("comms/data.csv") |> DataFrame
    num_rows, num_columns = size(df)

    for i in 1:num_rows
        push!(selectable_state, false)
        push!(data, [string(df[i, 1]), string(df[i, 2]), string(df[i, 3]), string(df[i, 4])])
    end

    updateLogs("Message List Updated")
end

function updateCSV()
    df = DataFrame(data, :auto)
    df = permutedims(df)

    csv_file_path = "comms/data.csv"

    try
        rename!(df, [:Number, :Date, :Time, :Message])
        CSV.write(csv_file_path, df)
    catch
        CSV.write(csv_file_path, df)
    end

    Refresh()
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
        updateLogs("No message selected")
        return
    end

    deleteat!(data, index_remove) #remove vector at index_remove
    deleteat!(selectable_state, index_remove) #remove state at index_remove

    updateLogs("Message Delete Successful!")

end

function updateLogs(a_log::String)
    # try
    push!(logs, a_log)
    # catch
    # end
end

function printLogs()
    for log in logs
        CImGui.TextColored(ImVec4(1.0, 1.0, 1.0, 1.0), "> ")
        CImGui.SameLine()
        CImGui.TextColored(ImVec4(1.0, 1.0, 0.0, 1.0), log)
    end
end

function processSerialResponse()
    sp = Any
    connected = false
    while !connected
        try
            global sp = LibSerialPort.open(portname, baudrate)
            connected = true
        catch e
            close(sp)
            println(e)
            updateLogs(e)
            sleep(0.5) #gives time to establish serial connection
        end

    end

    sp_flush(sp, SP_BUF_BOTH) #discards left over bytes waiting at the port, both input and output buffer
    serial_response = ""
    while true
        # try
        if bytesavailable(sp) > 0 #if buffer is empty ignore code below if statement
            # println("hi")
            chars = read(sp, Char)
            serial_response = serial_response * string(chars)
            if chars != '>'
                continue
            end

            # println(bytesavailable(sp))
            # serial_response = readuntil(sp, '>') #blocking until '>'
            serial_response = serial_response[1:end-1]
            serial_response = replace(serial_response, '\x00' => "")

            println(serial_response)
            if !isempty(serial_response)
                @match serial_response[1:2] begin
                    "L:" => begin
                        global lcd_status = "Connected"
                    end

                    "N:" => begin
                        global network_status = split(serial_response[22:end], ',')
                    end

                    "M:" => begin
                        message_details = serial_response[3:end]
                        phone_number = message_details[8:21]
                        date_and_time = split(serialResponse[28:47])
                        m_date = date_and_time[0]
                        m_time = date_and_time[1]
                        mess = message_details[50:end]

                        push!(data, [phone_number, m_date, m_time, mess])
                        updateCSV()
                    end

                    _ => updateLogs(serial_response)
                end
                # global serial_response = ""
            end
        end
        # println("buffer empty")
        # catch e
        # updateLogs(e)
        # end
        sleep(0.1)
    end
    close(sp)
    # end
end

serialResponse = Threads.@spawn processSerialResponse()

try
    demo_open = true
    clear_color = Cfloat[0.45, 0.55, 0.60, 1.00]
    Refresh()

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

        if lcd_status == "Connected"
            CImGui.TextColored((0.0, 1.0, 0.0, 1.0), lcd_status)
        else
            CImGui.TextColored((1.0, 0.0, 0.0, 1.0), lcd_status)
        end

        CImGui.SameLine()
        CImGui.TextColored((1.0, 1.0, 0.5, 1.0), "Network Status: ")
        CImGui.SameLine()

        if network_status == "No Network"
            CImGui.TextColored((1.0, 0.0, 0.0, 1.0), network_status)
        else
            CImGui.TextColored((0.0, 1.0, 0.0, 1.0), network_status)
        end

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
                if CImGui.Selectable("Phone Number: $(data[row_index][1])\nDate: $(data[row_index][2])\nTime: $(data[row_index][3])", selectable_state[row_index], 0) #create selectable
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
            for counter in eachindex(data) #deselect selectables 
                global selectable_state[counter] = false
            end

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
            updateLogs("Sending to LCD1")
            if message_index != 0
                message_to_send = data[message_index][3] * "\n"
                try
                    LibSerialPort.open(portname, baudrate) do sp
                        sleep(2) #gives time to establish serial connection
                        sp_flush(sp, SP_BUF_BOTH) #discards left over bytes waiting at the port, both input and output buffer
                        write(sp, "L1:$message_to_send")
                        updateLogs("Message sent to port")

                        # serial_response = readline(sp)

                        # if !isempty(serial_response)
                        #     println(serial_response)
                        #     updateLogs("Successful\nResponse: $serial_response")
                        # else
                        #     updateLogs("Failed! No Response")
                        # end
                    end
                catch e
                    println(e)
                    updateLogs(string(e))
                end
            else
                println("No message selected") #send to logs later
                updateLogs("No message selected")
            end
        end

        CImGui.SameLine()

        if CImGui.Button("Delete Message")
            DeleteMessage()
        end

        CImGui.Separator()

        if message_index != 0
            CImGui.TextWrapped(data[message_index][4])

        else
            CImGui.TextWrapped("")
        end

        CImGui.EndChild()

        CImGui.BeginChild("Logs", (width[] * 0.784, height[] * 0.465), true)
        CImGui.TextColored((1.0, 0.8, 0.0, 1.0), "Logs")
        CImGui.Separator()

        printLogs()

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

        sleep(0.1)
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