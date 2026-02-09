local Types = {}

export type SourcemapInstance = {
	name: string,
	className: string,
	pluginManaged: boolean?,
	filePaths: {string}?,
	children: {SourcemapInstance}?,
}

return Types