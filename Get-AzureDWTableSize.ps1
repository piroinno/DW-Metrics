####################### 
function Get-Type 
{ 
    param($type) 
 
$types = @( 
'System.Boolean', 
'System.Byte[]', 
'System.Byte', 
'System.Char', 
'System.Datetime', 
'System.Decimal', 
'System.Double', 
'System.Guid', 
'System.Int16', 
'System.Int32', 
'System.Int64', 
'System.Single', 
'System.UInt16', 
'System.UInt32', 
'System.UInt64') 
 
    if ( $types -contains $type ) { 
        Write-Output "$type" 
    } 
    else { 
        Write-Output 'System.String'         
    } 
} #Get-Type 
 
####################### 
<# 
.SYNOPSIS 
Creates a DataTable for an object 
.DESCRIPTION 
Creates a DataTable based on an objects properties. 
.INPUTS 
Object 
    Any object can be piped to Out-DataTable 
.OUTPUTS 
   System.Data.DataTable 
.EXAMPLE 
$dt = Get-psdrive| Out-DataTable 
This example creates a DataTable from the properties of Get-psdrive and assigns output to $dt variable 
.NOTES 
Adapted from script by Marc van Orsouw see link 
Version History 
v1.0  - Chad Miller - Initial Release 
v1.1  - Chad Miller - Fixed Issue with Properties 
v1.2  - Chad Miller - Added setting column datatype by property as suggested by emp0 
v1.3  - Chad Miller - Corrected issue with setting datatype on empty properties 
v1.4  - Chad Miller - Corrected issue with DBNull 
v1.5  - Chad Miller - Updated example 
v1.6  - Chad Miller - Added column datatype logic with default to string 
v1.7 - Chad Miller - Fixed issue with IsArray 
.LINK 
http://thepowershellguy.com/blogs/posh/archive/2007/01/21/powershell-gui-scripblock-monitor-script.aspx 
#> 
function Out-DataTable 
{ 
    [CmdletBinding()] 
    param([Parameter(Position=0, Mandatory=$true, ValueFromPipeline = $true)] [PSObject[]]$InputObject) 
 
    Begin 
    { 
        $dt = new-object Data.datatable   
        $First = $true  
    } 
    Process 
    { 
        foreach ($object in $InputObject) 
        { 
            $DR = $DT.NewRow()   
            foreach($property in $object.PsObject.get_properties()) 
            {   
                if ($first) 
                {   
                    $Col =  new-object Data.DataColumn   
                    $Col.ColumnName = $property.Name.ToString()   
                    if ($property.value) 
                    { 
                        if ($property.value -isnot [System.DBNull]) { 
                            $Col.DataType = [System.Type]::GetType("$(Get-Type $property.TypeNameOfValue)") 
                         } 
                    } 
                    $DT.Columns.Add($Col) 
                }   
                if ($property.Gettype().IsArray) { 
                    $DR.Item($property.Name) =$property.value | ConvertTo-XML -AS String -NoTypeInformation -Depth 1 
                }   
               else { 
                    $DR.Item($property.Name) = $property.value 
                } 
            }   
            $DT.Rows.Add($DR)   
            $First = $false 
        } 
    }  
      
    End 
    { 
        Write-Output @(,($dt)) 
    } 
 
}
function Get-Table
{
    [CmdletBinding()]
    Param
    (
        [string] $TableName,
        [string[]] $ColumnNames,
        [Collections.ArrayList] $DataSet
    )

    begin{
        #Create Table object
        $Table = New-Object system.Data.DataTable $TableName
    }

    process{
        #Define Columns
        foreach($ColumnName in $ColumnNames)
        {
            $Col = New-Object system.Data.DataColumn $ColumnName,([string])
            $Table.Columns.Add($Col)
        }

        foreach($Data in $DataSet)
        {
            #Create a row
            $row = $Table.NewRow()

            foreach($Key in $Data.Keys)
            {
                #Enter data in the row
                $row[$Key] = $Data[$Key]
            }
            #Add the row to the table
            $Table.Rows.Add($row)
        }
    }

    end{
        #Display the table
        return $Table
    }
}

Function Get-AzureDWTableSize
{
    [CmdletBinding()]
    Param
    (
        [string] [Parameter(Mandatory=$true)] $ServerName,
        [string] [Parameter(Mandatory=$true)] $DbName,
        [string] [Parameter(Mandatory=$true)] $UserName,
        [string] [Parameter(Mandatory=$true)] $UserPassword
    )

    begin{
        $Query = "SELECT  SCHEMA_NAME([schema_id]) AS 'SchemaName', [name] AS 'TableName' FROM sys.tables WHERE [type] = 'U'"
    }

    process {
        $TableList = Invoke-Sqlcmd $Query -ServerInstance $ServerName -Database $DbName -Username $UserName -Password $UserPassword | Out-DataTable
        $DataTableList = New-Object System.Collections.ArrayList
        $TableHeader = "TableName","NumberOfRows","DataSpace(GB)","IndexSpace(GB)","ReservedSpace(GB)","UnsedSpace(GB)"

        Foreach($RowA in $TableList.Rows)
        {
            $MyQuery = "DBCC PDW_SHOWSPACEUSED('[$($RowA[0].ToString())].[$($RowA[1].ToString())]')"
            $MyDataTable = Invoke-Sqlcmd $MyQuery -ServerInstance $ServerName -Database $DbName -Username $UserName -Password $UserPassword | Out-DataTable
    
            $NumberOfRows = 0
            $DataSpace = 0
            $IndexSpace = 0
            $ReservedSpace = 0
            $UnsedSpace = 0
            Foreach($Row in $MyDataTable.Rows)
            {
                $NumberOfRows = $NumberOfRows + $Row["ROWS"]
                $DataSpace = $DataSpace + $Row["DATA_SPACE"]
                $IndexSpace = $IndexSpace + $Row["INDEX_SPACE"]
                $ReservedSpace = $ReservedSpace + $Row["RESERVED_SPACE"]
                $UnsedSpace = $UnsedSpace + $Row["UNUSED_SPACE"]
            }
            $null = $DataTableList.Add(@{TableName="[$($RowA[0].ToString())].[$($RowA[1].ToString())]";NumberOfRows=$NumberOfRows;"DataSpace(GB)"=($DataSpace / 1024 / 1024);"IndexSpace(GB)"=($IndexSpace / 1024 / 1024);"ReservedSpace(GB)"=($ReservedSpace / 1024 / 1024);"UnsedSpace(GB)"=($UnsedSpace / 1024 / 1024);})
        }

        $table = Get-Table -TableName "$($DbName)_tables" -ColumnNames $TableHeader -DataSet $DataTableList
        $table | Sort-Object -Property "ReservedSpace(GB)" -Descending | format-table -AutoSize
        $Path = $env:TMP
        $FilePath = "$($Path)$($DbName)_tables.csv"
        Write-Host "Saving data to disk $($FilePath)"
        $tabCsv = $table | export-csv $FilePath -noType
    }

    end{
        return $tabCsv
    }
}