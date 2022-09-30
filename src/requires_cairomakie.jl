@info "TwPrototypes: loading CairoMakie utils"
using .CairoMakie # syntax by Requires.jl otherwise warning
# using CairoMakie
using Parameters: @with_kw
import KernelDensity


"""
    cm2inch(x)
    cm2inch(x1, x2, x...)

Convert length in cm to inch units: 1 inch = 2.54  
The single argument returns a value, the multiple argument version a Tuple.
"""
cm2inch(x) = x/2.54
#cm2inch(x1, x2, args...) = (cm2inch(x) for x in (x1,x2,args...))
cm2inch(x1, x2, args...) = Tuple(cm2inch(x) for x in (x1,x2,args...))

const golden_ratio = 1.618

@with_kw struct MakieConfig{FT,IT} 
    target::Symbol            = :paper
    pt_per_unit::FT           = 0.75   
    filetype::String          = "png"
    fontsize::IT              = 9
    size_inches::Tuple{FT,FT} = cm2inch.((17.5,17.5/golden_ratio))
end

#ppt_MakieConfig(;target = :presentation, pt_per_unit = 0.75/2, filetype = "png", fontsize=18, size_inches = cm2inch.((29,29/golden_ratio)), kwargs...) = MakieConfig(;target, pt_per_unit, filetype, fontsize, size_inches, kwargs...)
ppt_MakieConfig(;target = :presentation, filetype = "png", fontsize=18, size_inches = cm2inch.((16,16/golden_ratio)), kwargs...) = MakieConfig(;target, filetype, fontsize, size_inches, kwargs...)
# size so that orginal size covers half a wide landscape slide of 33cm
# svg does not work properly with fonts in ppt/wps

paper_MakieConfig(size_inches = cm2inch.((8.3,8.3/golden_ratio)), kwargs...) = MakieConfig(;size_inches, kwargs...)

"""
    pdf_figure = (size_inches = cm2inch.((8.3,8.3/golden_ratio)); fontsize=9,pt_per_unit = 0.75)
    pdf_figure_axis = (size_inches = cm2inch.((8.3,8.3/golden_ratio)); fontsize=9, pt_per_unit = 0.75, kwargs...)

Creates a figure with specified resolution and fontsize 
for given figure size. 
`pdf_figure_axis`, in addition returns an Axis created with kwargs.
They uses by default `pt_per_unit=0.75` to conform to png display and save. Remember to devide fontsize and other sizes specified elsewhere by this factor.
See also [`cm2inch`](@ref) and `save`.
"""    
function pdf_figure_axis(args...; makie_config::MakieConfig = MakieConfig(), kwargs...) 
    fig = pdf_figure(args...; makie_config)
    fig, Axis(fig[1,1]; kwargs...)
end

function pdf_figure(; makie_config::MakieConfig = MakieConfig())
    (;pt_per_unit, fontsize, size_inches) = makie_config
    resolution = 72 .* size_inches ./ pt_per_unit # size_pt
    fig = Figure(;resolution, fontsize = fontsize./ pt_per_unit)
end
function pdf_figure(size_inches::NTuple{2}; makie_config::MakieConfig = MakieConfig())
    makie_config = MakieConfig(makie_config; size_inches)
    pdf_figure(;makie_config)
end
function pdf_figure(width2height::Number; makie_config::MakieConfig = MakieConfig())
    size_inches = (makie_config.size_inches[1], makie_config.size_inches[1]/width2height)
    makie_config = MakieConfig(makie_config; size_inches)
    pdf_figure(;makie_config)
end

"""
    save_with_config(filename, fig; makie_config = MakieConfig(), args...)

Save figure with file extension `cfg.filetype` to subdirectory `cfg.filetype`
of given path of filename
"""
function save_with_config(filename::AbstractString, fig::Union{Figure, Makie.FigureAxisPlot, Scene}; makie_config = MakieConfig(), args...)
    local cfg = makie_config
    pathname, ext = splitext(filename) 
    ext != "" && @warn "replacing extension $ext by $(cfg.filetype)"
    bname = basename(pathname) * "." *  cfg.filetype
    dir = joinpath(dirname(pathname), string(cfg.target))
    filename_cfg = joinpath(dir,bname)
    mkpath(dir)
    #save(filename_cfg, fig, args...)
    save(filename_cfg, fig, args...; pt_per_unit = makie_config.pt_per_unit)
    filename_cfg
end

"""
    hidexdecoration!(ax;, label, ticklabels, ticks, grid, minorgrid, minorticks; kwargs...)
    hideydecoration!(ax;, label, ticklabels, ticks, grid, minorgrid, minorticks; kwargs...)

Versions of hidexdecorations! and hideydecorations! with defaults reversed.
This allows to selectively hide single decorations, e.g. only the label.
"""
hidexdecoration!(ax; label = false, ticklabels = false, ticks = false, grid = false, minorgrid = false, minorticks = false, kwargs...) = hidexdecorations!(ax, label, ticklabels, ticks, grid, minorgrid, minorticks, kwargs...)

hideydecoration!(ax; label = false, ticklabels = false, ticks = false, grid = false, minorgrid = false, minorticks = false, kwargs...) = hideydecorations!(ax; label, ticklabels, ticks, grid, minorgrid, minorticks, kwargs...)

"""
Extract axis object from given figure position. Works recursively until an 
Axis-object is returned
"""
axis_contents(axis::Axis) = axis
axis_contents(figpos::GridLayout) = axis_contents(first(contents(figpos)))
axis_contents(figpos::GridPosition) = axis_contents(first(contents(figpos)))


passnothing(f) = (xs...) -> any(isnothing, xs) ? nothing : f(xs...)

# plot density from MCMCChains.value
function density_params(chns, pars=names(chns, :parameters); 
    makie_config::MakieConfig=MakieConfig(), 
    fig = pdf_figure(cm2inch.((8.3,8.3/1.618)); makie_config), 
    column = 1, xlims=nothing, 
    labels=nothing, colors = nothing, ylabels = nothing, normalize = false, 
    kwargs_axis = repeat([()],length(pars)), kwargs...
    )
    n_chains = size(chns,3)
    n_samples = length(chns)
    labels_ch = isnothing(labels) ? string.(1:n_chains) : labels
    ylabels = isnothing(ylabels) ? string.(pars) : ylabels
    !isnothing(xlims) && (length(xlims) != length(pars)) && error(
        "Expected length(xlims)=$(length(xlims)) (each a Tuple or nothing) to be length(pars)=$(length(pars))")
    for (i, param) in enumerate(pars)
        ax = Axis(fig[i, column]; ylabel=ylabels[i], kwargs_axis[i]...)
        if isnothing(colors)
            colors = ax.palette.color[]
        end
        for i_chain in 1:n_chains
            _values = chns[:, param, i_chain]
            col = colors[i_chain]
            if normalize
                k = KernelDensity.kde(_values)
                md = maximum(k.density)
                lines!(ax, k.x, k.density ./ md; label=labels_ch[i_chain], color = col, kwargs...)
            else
                density!(ax, _values; label=labels_ch[i_chain], color = (col, 0.3), strokecolor = col, strokewidth = 1, 
                #strokearound = true,
                kwargs...)
            end
        end
        xlim = passnothing(getindex)(xlims, i)
        !isnothing(xlim) && xlims!(ax, xlim)
    #hideydecorations!(ax,  ticklabels=false, ticks=false, grid=false)
        hideydecorations!(ax, label=false, ticklabels=true)
        # if i < length(params)
        #     hidexdecorations!(ax; grid=false)
        # else
        #     ax.xlabel = "Parameter estimate"
        # end
    end
    # axes = [only(contents(fig[i, 2])) for i in 1:length(params)]
    # linkxaxes!(axes...)
    #axislegend(only(contents(fig[2, column])))
    fig    
end

