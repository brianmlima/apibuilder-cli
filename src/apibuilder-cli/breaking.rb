require 'ostruct'

module ApibuilderCli


  class SpecHash
    def SpecHash.nameKey()
      "name"
    end

    def SpecHash.name(hash)
      hash["name"]
    end

    def SpecHash.modelsKey()
      "models"
    end

    def SpecHash.models(hash)
      hash["models"]
    end

    def SpecHash.enumsKey()
      "enums"
    end

    def SpecHash.enums(hash)
      hash["enums"]
    end


    RESOURCES_KEY = "resources"

    def SpecHash.resources(hash)
      hash[SpecHash::RESOURCES_KEY]
    end

    PATH_KEY = "path"

    def SpecHash.path(hash)
      hash[SpecHash::PATH_KEY]
    end

    OPERATIONS_KEY = "operations"

    def SpecHash.operations(hash)
      hash[SpecHash::OPERATIONS_KEY]
    end


    def SpecHash.fieldsKey()
      "fields"
    end

    def SpecHash.fields(hash)
      hash["fields"]
    end

    def SpecHash.requiredKey()
      "required"
    end

    def SpecHash.required(hash)
      if (hash.has_key?(requiredKey)) then
        hash[requiredKey]
      else
        true
      end
    end

    def SpecHash.valuesKey()
      "values"
    end

    def SpecHash.values(hash)
      hash["values"]
    end

    def SpecHash.typeKey()
      "type"
    end

    def SpecHash.type(hash)
      hash["type"]
    end
  end

  class SpecTool

    class ModelUtil

      PRIMITIVES = ["boolean", "date-iso8601", "date-time-iso8601", "decimal", "double", "integer", "json", "long", "object", "string", "unit"]

      def ModelUtil.isModel(aType)
        if (ModelUtil::PRIMITIVES.include?("aType"))
          # Is a primitive
          return false
        end
        if (aType[0] == "[")

          return false
        end
        return true
      end
    end


    # finds a field in a model hash by field name
    def SpecTool.findFieldByName(model, fieldName)
      SpecHash.fields(model).each do |field|
        if (fieldName == SpecHash.name(field))
          return field
        end
      end
      return nil
    end


    # finds an enum in a data hash by enum name
    def SpecTool.findEnumByName(data, enumName)
      SpecHash.enums(data).each_pair { |name, enum|
        if (name == enumName)
          return enum
        end
      }
      return nil
    end

    # finds an enum entry in an enum hash by value
    def SpecTool.findEnumEntryByValue(enum, enumValue)
      SpecHash.values(enum).each { |enumEntry|
        if (SpecHash.name(enumEntry) == SpecHash.name(enumValue))
          return enumEntry
        end
      }
      return nil
    end

    def SpecTool.findLocalOperation(remoteOperation, localResource)
      remoteMethod = remoteOperation["method"]
      remotePath = SpecHash.path(remoteOperation)
      SpecHash.operations(localResource).each do |localOperation|
        localMethod = localOperation["method"]
        localPath = SpecHash.path(localOperation)
        if (remoteMethod == localMethod && remotePath == localPath)
          return localOperation
        end
      end
      return nil
    end


    def SpecTool.compare(remoteData, localData)

      breakingChanges = Array.new
      brokenModels = Array.new

      #############################################
      # Check enumerations
      SpecHash.enums(remoteData).each_pair {
          |remoteEnumName, remoteEnum|
        localEnum = findEnumByName(localData, remoteEnumName)
        if (localEnum == nil)
          brokenModels.push(remoteModelName)
          breakingChanges.push("enums.#{remoteEnumName} does not exist locally")
          next
        end

        SpecHash.values(remoteEnum).each { |remoteEnumValue|
          localEnumValue = findEnumEntryByValue(localEnum, remoteEnumValue)

          if (localEnumValue == nil)
            brokenModels.push(remoteEnum)
            breakingChanges.push("#{remoteEnumName}.values[].name.#{SpecHash.name(remoteEnumValue)} does not exist locally")
            next
          end
        }
      }
      #############################################

      #############################################
      # Iterate over the remote models
      ::ApibuilderCli::SpecHash.models(remoteData).each_pair {
          |remoteModelName, remoteModel|
        #puts "#{remoteModleName} #{localData[modelsKey].key?(remoteModleName)}"

        localModel = ::ApibuilderCli::SpecHash.models(localData)[remoteModelName]
        remoteFields = ::ApibuilderCli::SpecHash.fields(remoteModel)
        localFields = ::ApibuilderCli::SpecHash.fields(localModel)

        #############################################
        # Iterate over the remote model fields
        remoteFields.each {
            |remoteField|
          remoteFieldName = ::ApibuilderCli::SpecHash.name(remoteField)
          localField = ::ApibuilderCli::SpecTool.findFieldByName(localModel, remoteFieldName)
          #Break if remote required field does not exist locally
          if (localField == nil)
            brokenModels.push(remoteModelName)
            breakingChanges.push("#{remoteModelName}.fields.#{remoteFieldName} does not exist locally")
            next
          end
          # field exist on both sides, do comparison
          remoteFieldType = ::ApibuilderCli::SpecHash.type(remoteField)
          localFieldType = ::ApibuilderCli::SpecHash.type(localField)
          #  Break if field type has changed
          if (remoteFieldType != localFieldType)
            brokenModels.push(remoteModelName)
            breakingChanges.push("#{remoteModelName}.fields.#{remoteFieldName} field type has changed from #{remoteFieldType} to  #{localFieldType}")
          end
          # Break if required has changed
          isRemoteFieldRequired = ::ApibuilderCli::SpecHash.required(remoteField)
          isLocalFieldRequired = ::ApibuilderCli::SpecHash.required(localField)
          if (isRemoteFieldRequired != isLocalFieldRequired)
            brokenModels.push(remoteModelName)
            breakingChanges.push("#{remoteModelName}.fields.#{remoteFieldName} field required has changed from #{isRemoteFieldRequired} to #{isLocalFieldRequired}")
          end
        }
      }

      remoteResources = SpecHash.resources(remoteData)
      localResources = SpecHash.resources(localData)

      remoteResources.each_pair {
          |remoteResourceName, remoteResource|
        if (!localResources.key?(remoteResourceName))
          breakingChanges.push("resources.#{remoteResourceName} has been removed")
          next
        end
        localResource = localResources.fetch(remoteResourceName)

        remoteResourcePath = SpecHash.path(remoteResource)
        localResourcePath = SpecHash.path(localResource)


        hasResourcePathChanged = !(remoteResourcePath == localResourcePath)
        if (hasResourcePathChanged)
          breakingChanges.push("resources.#{remoteResourceName} path has changed from "\
                               "#{ (remoteResourcePath == nil) ? "Not Defined (defaults to \"#{remoteResourceName}\")" : remoteResourcePath } "\
                               "to #{ (localResourcePath == nil) ? "Not Defined (defaults to \"#{remoteResourceName}\")" : localResourcePath }")
        end


        SpecHash.operations(remoteResource).each {
            |remoteOperation|
          remoteMethod = remoteOperation["method"]
          remotePath = SpecHash.path(remoteOperation)
          localOperation = SpecTool.findLocalOperation(remoteOperation, localResource)
          if (localOperation == nil)
            breakingChanges.push("resources.#{remoteResourceName}.operation{ method: #{remoteMethod} : path: #{remotePath}  }  has been removed")
            next
          end
          if(hasResourcePathChanged)
            breakingChanges.push("resources.#{remoteResourceName}.operation{ method: #{remoteMethod} : path: #{remotePath}  }  relative path has changed at the #{remoteResourceName} resource path")
          end


        }
      }


      #############################################
      # Handle output nothing and exist success
      # or output breaking changes
      if (!breakingChanges.empty?)
        puts breakingChanges
        exit(1)
      else
        exit(0)
      end
      #############################################

    end
  end
end
