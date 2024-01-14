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
battery_level::String = "Not Found"

lcd_data::String = ""

# for serial communication
portname::String = if Sys.iswindows()
    "COM5"
elseif Sys.isapple()
    "/dev/cu.usbserial-1410"
else
    error("Unknown OS detected!\nSupported OS include: Windows and macOS")
end

global baudrate = 9600 #can change. VERY IMPORTANT!

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
    sleep(5) #give GUI time to load up, make gui load faster
    while true #check if port available
        try
            sp = LibSerialPort.open(portname, baudrate)
            close(sp)
            updateLogs("Port $portname: Available!")
            break
        catch e
            updateLogs("Port $portname: Unavailable!\nReconnecting....")
            sleep(5)
        end
    end

    try
        LibSerialPort.open(portname, baudrate) do sp
            updateLogs("Port $portname: Connection established!")
            serial_ref::Ref{String} = Ref("")
            updateLogs("Discarding data remnants....")
            sleep(2) #add time delay for nice effect
            try
                sp_flush(sp, SP_BUF_BOTH)  #discards left over bytes waiting at the port, both input and output buffer
            catch e
                updateLogs(e)
                println(e)
            end
            updateLogs("Data remnants discarded")

            opened = true
            # function handleIncomingData(serial_ref::Ref{String})
            # println("Hello Me")
            while true
                try
                    if length(lcd_data) > 0
                        write(sp, "L1:$lcd_data")
                        updateLogs("Message sent to port")
                        global lcd_data = ""
                    end
                catch
                end
                try
                    if bytesavailable(sp) > 0 #if buffer is empty ignore code below if statement
                        # println("Hello")
                        chars = read(sp, Char)

                        if chars == '\0' #ignore embedded nulls
                            continue
                        end

                        # check for beginning and end of serial input using '<' and '>'
                        if chars == '<'
                            global opened = true
                            continue

                        elseif chars == '>'
                            global opened = false
                        end

                        if opened
                            try
                                serial_ref[] = serial_ref[] * string(chars)
                                continue
                            catch
                                println("serial_ref concatenation is the error")
                            end
                        end

                        try
                            println(serial_ref[])
                            if length(serial_ref[]) == 1
                                continue
                            end
                            # println(serial_response[1:2])
                        catch e
                            println("Length error stuff")
                            println(e)
                        end
                        try
                            if serial_ref[][1] == '.'
                                serial_ref[] = serial_ref[][2:end]
                            end
                        catch
                            println("Removing '.' caused the error!")
                        end


                        println(serial_ref)

                        if !isempty(serial_ref[])
                            @match serial_ref[][1:2] begin #check if idnetifier matches any of the patterns
                                "L:" => begin
                                    try
                                        updateLogs(serial_ref[][3:end])
                                        updateLogs("LCD Status incoming....")
                                        global lcd_status = "Connected"
                                        global serial_ref[] = ""
                                    catch e
                                        println(e)
                                        updateLogs(e)
                                    end

                                end

                                "B:" => begin
                                    try
                                        updateLogs(serial_ref[])
                                        # updateLogs("Battery Status Incoming....")
                                        sleep(1)
                                        index_start = findfirst("+CBC: ", serial_ref[])[end] + 1
                                        sub_ref = serial_ref[][index_start:end]
                                        sub_ref_split = split(sub_ref, ',')
                                        global battery_level = "$(sub_ref_split[2])/100"
                                    catch e
                                        global battery_level = "Not Found"
                                        println(e)
                                        updateLogs(e)
                                    end
                                end

                                "N:" => begin
                                    try
                                        # global network_status = split(serial_ref[][22:end], ',')
                                        updateLogs(serial_ref[])
                                        # updateLogs("Network Status Incoming....")
                                        sleep(1)
                                        index_start = findfirst("+CSQ: ", serial_ref[])[end] + 1
                                        sub_ref = serial_ref[][index_start:end]
                                        network_level = round(Int, (parse(Int, split(sub_ref, ',')[1]) / 31) * 100)
                                        global network_status = "$network_level/100"
                                        global serial_ref[] = ""
                                    catch e
                                        global network_status = "No Network"
                                        println(e)
                                        updateLogs(e)
                                    end

                                end

                                "M:" => begin
                                    try
                                        updateLogs("Message Incoming...")
                                        sleep(2)
                                        updateLogs(serial_ref[])

                                        index_start = findfirst("+CMT: ", serial_ref[])[end] + 1
                                        sub_ref = serial_ref[][index_start:end]
                                        data_split = split(sub_ref, ',')
                                        phone_number = "+" * data_split[1][2:end-1]
                                        println(phone_number)
                                        m_date = data_split[3][2:end]
                                        println(m_date)
                                        m_time_mess = split(data_split[4], '\r')
                                        m_time = m_time_mess[1][2:end-3]
                                        println(m_time)
                                        mess = m_time_mess[2]
                                        println(mess)

                                        updateLogs("Phone number: $phone_number\nDate: $m_date\nTime: $m_time")

                                        push!(data, [phone_number, m_date, m_time, mess])
                                        updateCSV()
                                        global serial_ref[] = ""
                                    catch e
                                        println(e)
                                        updateLogs(e)
                                    end

                                end

                                _ => begin
                                    try
                                        updateLogs(serial_ref[])
                                        println(serial_ref[])
                                        global serial_ref[] = ""
                                    catch e
                                        println(e)
                                        updateLogs(e)
                                    end
                                end
                            end
                            # global serial_ref[] = ""
                        end
                    end
                catch e
                    println(e)
                    updateLogs(e)
                end
                sleep(0.01)
            end
            # end
            # handleIncomingData(serial_ref)
        end
    catch e
        println(e)
        updateLogs(e)
    end
end
# @async processSerialResponse()

Threads.@spawn processSerialResponse()

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
        CImGui.TextColored((1.0, 1.0, 0.7, 1.0), "LCD Status: ")
        CImGui.SameLine()

        CImGui.TextColored((1.0, 1.0, 0.0, 1.0), lcd_status)

        CImGui.SameLine()
        CImGui.TextColored((1.0, 1.0, 0.7, 1.0), "Network Level: ")
        CImGui.SameLine()

        CImGui.TextColored((1.0, 1.0, 0.0, 1.0), network_status)

        CImGui.SameLine()
        CImGui.TextColored((1.0, 1.0, 0.7, 1.0), "Battery Level: ")
        CImGui.SameLine()

        CImGui.TextColored((1.0, 1.0, 0.0, 1.0), battery_level)

        CImGui.EndChild()

        CImGui.BeginChild("Main Window", (width[] * 0.989, height[] * 0.941), false)

        CImGui.BeginChild("ReceiverSection", (width[] * 0.2, height[] * 0.941), true)

        CImGui.BeginTabBar("Tabs")

        if CImGui.BeginTabItem("Received")

            CImGui.TextColored((0.0, 1.0, 0.0, 1.0), "Received Messages")
            CImGui.SameLine(0.0, -1)

            CImGui.PushStyleVar(CImGui.ImGuiStyleVar_FrameRounding, 10.0)

            # if CImGui.Button("Refresh")
            #     Refresh()
            # end

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
                global lcd_data = message_to_send
                # try
                #     LibSerialPort.open(portname, baudrate) do sp
                #         # sleep(0.2) #gives time to establish serial connection
                #         sp_flush(sp, SP_BUF_BOTH) #discards left over bytes waiting at the port, both input and output buffer
                #         write(sp, "L1:$message_to_send")
                #         updateLogs("Message sent to port")

                #         # serial_response = readline(sp)

                #         # if !isempty(serial_response)
                #         #     println(serial_response)
                #         #     updateLogs("Successful\nResponse: $serial_response")
                #         # else
                #         #     updateLogs("Failed! No Response")
                #         # end
                #     end
                # catch e
                #     println(e)
                #     updateLogs(string(e))
                # end
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

        sleep(0.01)
    end
catch e
    @error "Error in renderloop!" exception = e
    updateLogs(e)
    Base.show_backtrace(stderr, catch_backtrace())
finally
    ImGuiOpenGLBackend.shutdown(gl_ctx)
    ImGuiGLFWBackend.shutdown(window_ctx)
    CImGui.DestroyContext(ctx)
    glfwDestroyWindow(window)

end
