<!---
License:
Copyright 2007 GreatBizTools, LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Copyright: GreatBizTools, LLC
$Id$

Created version: 1.5.0
Updated version: 1.5.0

Notes:
--->
<cfcomponent
	displayname="CacheClearCommand"
	extends="MachII.framework.Command"
	output="false"
	hint="A Command for clearing caching.">

	<!---
	PROPERTIES
	--->
	<cfset variables.commandType = "cache-clear" />
	<cfset variables.alias = "" />
	<cfset variables.condition = "" />
	
	<!---
	INITIALIZATION / CONFIGURATION
	--->
	<cffunction name="init" access="public" returntype="CacheClearCommand" output="false"
		hint="Initializes the command.">
		<cfargument name="alias" type="string" required="false" default="" />
		<cfargument name="condition" type="string" required="false" default="" />

		<cfset setAlias(arguments.alias) />
		<cfset setCondition(arguments.condition) />

		<cfreturn this />
	</cffunction>

	<!---
	PUBLIC FUNCTIONS
	--->
	<cffunction name="execute" access="public" returntype="boolean" output="false"
		hint="Executes a caching block.">
		<cfargument name="event" type="MachII.framework.Event" required="true" />
		<cfargument name="eventContext" type="MachII.framework.EventContext" required="true" />
		
		<cfset var continue = true />
		<cfset var cacheManager = arguments.eventContext.getAppManager().getCacheManager() />
		
		<cfif NOT Len(getCondition()) OR evaluate(getCondition())>
			<cfset cacheManager.clearCachesByAlias(getAlias()) />
		</cfif>
		
		<cfreturn continue />
	</cffunction>
	
	<!---
	ACCESSORS
	--->
	<cffunction name="setAlias" access="private" returntype="void" output="false">
		<cfargument name="alias" type="string" required="true" />
		<cfset variables.alias = arguments.alias />
	</cffunction>
	<cffunction name="getAlias" access="private" returntype="string" output="false">
		<cfreturn variables.alias />
	</cffunction>
	
	<cffunction name="setCondition" access="private" returntype="void" output="false">
		<cfargument name="condition" type="string" required="true" />
		<cfset variables.condition = arguments.condition />
	</cffunction>
	<cffunction name="getCondition" access="private" returntype="string" output="false">
		<cfreturn variables.condition />
	</cffunction>

</cfcomponent>